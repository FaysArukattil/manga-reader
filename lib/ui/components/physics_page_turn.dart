import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ============================================================================
// TUNABLE PHYSICS & VISUAL CONSTANTS
// ============================================================================
/// Spring stiffness for page settle animation. Higher = snappier snap.
const double kSpringStiffness = 380.0;

/// Spring damping. Higher = less oscillation/overshoot; lower = bouncier.
const double kSpringDamping = 32.0;

/// Mass of the paper page.
const double kSpringMass = 1.0;

/// Fraction of screen width dragged to trigger page turn on slow release (0.0 - 1.0).
const double kCompletionThreshold = 0.40;

/// Minimum fling velocity (pixels/second) to complete a turn regardless of distance.
const double kFlingVelocityThreshold = 450.0;

/// Maximum corner curl angle in radians (~14 degrees) when dragged from top/bottom.
const double kMaxCurlAngle = 0.24;

/// Maximum opacity of the cast drop shadow onto the underneath page.
const double kShadowOpacity = 0.65;

/// Rubber-band bounce distance factor when trying to turn past boundaries.
const double kRubberBandFactor = 0.18;

// ============================================================================
// WIDGET
// ============================================================================

typedef PageBuilder = Widget Function(BuildContext context, int index);

class PhysicsPageTurnController extends ChangeNotifier {
  _PhysicsPageTurnState? _state;

  void _attach(_PhysicsPageTurnState state) => _state = state;
  void _detach() => _state = null;

  int get currentPage => _state?._currentIndex ?? 0;

  void jumpToPage(int page) => _state?._jumpTo(page);

  void nextPage() => _state?._turnPage(forward: true);

  void prevPage() => _state?._turnPage(forward: false);
}

/// Realistic 3D physical book reader page turn:
/// - The current viewing manga page itself physically bends and curls in 3D space.
/// - Dynamic perspective distortion and lighting gradients as the paper arches.
/// - Reverse side of the manga page features paper texture and translucent ink bleed-through.
/// - Next page is revealed underneath with soft ambient occlusion drop shadow.
/// - Opaque paper bounds so underneath images never leak through.
/// - Zero-latency audio trigger the instant a page flip begins.
class PhysicsPageTurn extends StatefulWidget {
  const PhysicsPageTurn({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.initialPage = 0,
    this.controller,
    this.rtl = false,
    this.pageFlipEffect = true,
    this.onPageChanged,
    this.onPageTurnStart,
    this.onPagePeel,
    this.onTurnCancel,
    this.onCenterTap,
  });

  final int itemCount;
  final PageBuilder itemBuilder;
  final int initialPage;
  final PhysicsPageTurnController? controller;
  final bool rtl;
  final bool pageFlipEffect;
  final ValueChanged<int>? onPageChanged;
  final void Function(double speed)? onPageTurnStart;
  final void Function(double speed)? onPagePeel;
  final VoidCallback? onTurnCancel;
  final VoidCallback? onCenterTap;

  @override
  State<PhysicsPageTurn> createState() => _PhysicsPageTurnState();
}

class _PhysicsPageTurnState extends State<PhysicsPageTurn>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _anim;

  /// Current turn progress:
  ///   0.0 = idle at current page
  ///  >0.0 = turning forward towards next page (settles to 1.0)
  ///  <0.0 = turning backward towards prev page (settles to -1.0)
  double _progress = 0.0;
  double _targetProgress = 0.0;

  /// Corner drag bias: -1.0 (top corner), 0.0 (center), +1.0 (bottom corner)
  double _cornerBias = 0.0;

  bool _isDragging = false;
  bool _peelSoundPlayed = false;
  bool _flipSoundPlayed = false;
  Offset _dragStart = Offset.zero;
  DateTime _lastDragTime = DateTime.now();
  double _lastRawProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex =
        widget.initialPage.clamp(0, math.max(0, widget.itemCount - 1)).toInt();
    widget.controller?._attach(this);

    _anim = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _progress = _anim.value;
        });
      });
  }

  @override
  void didUpdateWidget(PhysicsPageTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    if (widget.initialPage != oldWidget.initialPage &&
        widget.initialPage != _currentIndex) {
      _jumpTo(widget.initialPage);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _anim.dispose();
    super.dispose();
  }

  void _jumpTo(int page) {
    final target = page.clamp(0, math.max(0, widget.itemCount - 1)).toInt();
    if (_currentIndex == target && _progress == 0.0) return;
    _anim.stop();
    setState(() {
      _currentIndex = target;
      _progress = 0.0;
    });
    widget.onPageChanged?.call(_currentIndex);
  }

  void _turnPage({required bool forward}) {
    if (_isDragging || _anim.isAnimating) return;
    final canTurn = forward
        ? (_currentIndex < widget.itemCount - 1)
        : (_currentIndex > 0);
    if (!canTurn) {
      _playRubberBand(forward: forward);
      return;
    }

    _cornerBias = 0.0;
    // Trigger sound instantly on turn start with crisp 1.1x rate
    widget.onPageTurnStart?.call(1.1);

    final target = forward ? 1.0 : -1.0;
    _animateTo(target, velocity: forward ? 2.5 : -2.5);
  }

  void _playRubberBand({required bool forward}) {
    _anim.stop();
    final bounce = forward ? 0.08 : -0.08;
    _progress = bounce;
    _animateTo(0.0, velocity: forward ? -1.5 : 1.5);
  }

  void _animateTo(double target, {double velocity = 0.0}) {
    _targetProgress = target;
    const spring = SpringDescription(
      mass: kSpringMass,
      stiffness: kSpringStiffness,
      damping: kSpringDamping,
    );
    final sim = SpringSimulation(spring, _progress, target, velocity);
    _anim.animateWith(sim).then((_) {
      if (mounted && !_isDragging) {
        _onTurnComplete();
      }
    });
  }

  void _onTurnComplete() {
    if (_targetProgress >= 0.9) {
      // Completed forward turn
      if (_currentIndex < widget.itemCount - 1) {
        _currentIndex++;
        widget.onPageChanged?.call(_currentIndex);
      }
    } else if (_targetProgress <= -0.9) {
      // Completed backward turn
      if (_currentIndex > 0) {
        _currentIndex--;
        widget.onPageChanged?.call(_currentIndex);
      }
    }
    _progress = 0.0;
    _anim.value = 0.0;
    _targetProgress = 0.0;
    _peelSoundPlayed = false;
    _flipSoundPlayed = false;
    setState(() {});
  }

  // ------------------------------------------------------------- Gestures

  void _handleDragStart(DragStartDetails details) {
    _anim.stop();
    _isDragging = true;
    _peelSoundPlayed = false;
    _flipSoundPlayed = false;
    _dragStart = details.localPosition;
    _lastDragTime = DateTime.now();
    _lastRawProgress = 0.0;
    final size = context.size ?? const Size(400, 800);
    final normY = (_dragStart.dy / size.height).clamp(0.0, 1.0);
    // Bias: -1 at top, +1 at bottom
    _cornerBias = ((normY - 0.5) * 2.0).clamp(-1.0, 1.0);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final size = context.size ?? const Size(400, 800);
    final totalDeltaX = details.localPosition.dx - _dragStart.dx;
    final now = DateTime.now();
    final dtMs = math.max(1, now.difference(_lastDragTime).inMilliseconds);
    _lastDragTime = now;

    // In LTR: dragging left (negative dx) turns forward (+progress)
    // In RTL: dragging right (positive dx) turns forward (+progress)
    final forwardSign = widget.rtl ? 1.0 : -1.0;
    double rawProgress = (totalDeltaX / size.width) * forwardSign;

    final dProg = (rawProgress - _lastRawProgress).abs();
    _lastRawProgress = rawProgress;
    final speed = ((dProg / (dtMs / 1000.0)) * 0.8).clamp(0.7, 1.6);

    // Boundary resistance (rubber banding)
    final isForward = rawProgress > 0;
    final canMove = isForward
        ? (_currentIndex < widget.itemCount - 1)
        : (_currentIndex > 0);

    if (!canMove) {
      final sign = rawProgress.sign;
      rawProgress = sign * math.pow(rawProgress.abs(), 0.6) * kRubberBandFactor;
    }

    // 1. If moved slightly (>= 4%): play subtle paper peel rustle
    if (!_peelSoundPlayed && rawProgress.abs() >= 0.04 && canMove) {
      _peelSoundPlayed = true;
      widget.onPagePeel?.call(speed);
    }

    // 2. If moved further (>= 22%): play page flip sound with speed modulation
    if (!_flipSoundPlayed && rawProgress.abs() >= 0.22 && canMove) {
      _flipSoundPlayed = true;
      widget.onPageTurnStart?.call(speed);
    }

    setState(() {
      _progress = rawProgress.clamp(-1.2, 1.2);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    final size = context.size ?? const Size(400, 800);
    final vx = details.velocity.pixelsPerSecond.dx;
    final forwardSign = widget.rtl ? 1.0 : -1.0;
    final normVelocity = (vx / size.width) * forwardSign;

    final isForward = _progress > 0;
    final canMove = isForward
        ? (_currentIndex < widget.itemCount - 1)
        : (_currentIndex > 0);

    if (!canMove) {
      widget.onTurnCancel?.call();
      _animateTo(0.0, velocity: normVelocity);
      return;
    }

    // Decision logic using BOTH drag distance threshold and fling velocity
    double target = 0.0;
    if (_progress.abs() > kCompletionThreshold) {
      if (isForward) {
        target = normVelocity < -kFlingVelocityThreshold / size.width ? 0.0 : 1.0;
      } else {
        target = normVelocity > kFlingVelocityThreshold / size.width ? 0.0 : -1.0;
      }
    } else {
      if (normVelocity > kFlingVelocityThreshold / size.width) {
        target = 1.0;
      } else if (normVelocity < -kFlingVelocityThreshold / size.width) {
        target = -1.0;
      } else {
        target = 0.0;
      }
    }

    if (target != 0.0) {
      if (!_flipSoundPlayed) {
        _flipSoundPlayed = true;
        final flingSpeed = (normVelocity.abs() * 0.4).clamp(0.85, 1.55);
        widget.onPageTurnStart?.call(flingSpeed);
      }
    } else {
      // Canceled / let go early: stop sound immediately
      widget.onTurnCancel?.call();
    }

    _animateTo(target, velocity: normVelocity);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isDragging || _anim.isAnimating) return;
    final size = context.size;
    if (size == null) return;

    final frac = details.localPosition.dx / size.width;
    if (frac < 0.28) {
      _turnPage(forward: widget.rtl);
    } else if (frac > 0.72) {
      _turnPage(forward: !widget.rtl);
    } else {
      widget.onCenterTap?.call();
    }
  }

  // ------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final hasNext = _currentIndex < widget.itemCount - 1;
    final hasPrev = _currentIndex > 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onTapUp: _handleTapUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          if (!widget.pageFlipEffect) {
            return _buildSlideTransition(size, hasNext, hasPrev);
          }

          return _build3DBookTurn(size, hasNext, hasPrev);
        },
      ),
    );
  }

  Widget _buildSlideTransition(Size size, bool hasNext, bool hasPrev) {
    final p = _progress.clamp(-1.0, 1.0);
    final sign = widget.rtl ? -1.0 : 1.0;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (p > 0 && hasNext)
            Positioned.fill(
              child: RepaintBoundary(
                child: _opaquePage(_currentIndex + 1),
              ),
            ),
          if (p < 0 && hasPrev)
            Positioned.fill(
              child: RepaintBoundary(
                child: _opaquePage(_currentIndex - 1),
              ),
            ),
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(-p * size.width * sign, 0),
              child: RepaintBoundary(
                child: _opaquePage(_currentIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opaque wrapper ensuring no transparency leaks between pages
  Widget _opaquePage(int index) {
    return Container(
      color: Colors.black,
      child: widget.itemBuilder(context, index),
    );
  }

  /// True 3D bending page turn where the current manga page physically curves
  /// in perspective space, showing front curl, spine shadow, and authentic back print.
  Widget _build3DBookTurn(Size size, bool hasNext, bool hasPrev) {
    final p = _progress.clamp(-1.0, 1.0);

    // Completely idle: render just the current page
    if (p == 0.0 && !_isDragging) {
      return RepaintBoundary(
        child: _opaquePage(_currentIndex),
      );
    }

    final isForward = p >= 0.0;
    final absP = p.abs();
    final isRtl = widget.rtl;

    // Spine alignment: LTR spine is on the left; RTL spine is on the right
    final spineAlignment =
        isRtl ? Alignment.centerRight : Alignment.centerLeft;

    if (isForward) {
      // Forward Turn:
      // - Underneath page: _currentIndex + 1
      // - Turning page: _currentIndex (rotates from 0 to -180 degrees)
      final underIndex = hasNext ? _currentIndex + 1 : _currentIndex;
      final turningIndex = _currentIndex;

      final angle = (isRtl ? 1.0 : -1.0) * absP * math.pi;
      final isBackFacing = absP > 0.5;

      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Underneath page (rests flat on book)
            Positioned.fill(
              child: RepaintBoundary(
                child: _opaquePage(underIndex),
              ),
            ),

            // 2. Dynamic cast drop shadow on the underneath page
            Positioned.fill(
              child: CustomPaint(
                painter: _CastPageShadowPainter(
                  progress: absP,
                  isRtl: isRtl,
                ),
              ),
            ),

            // 3. The 3D Bending Page itself
            Positioned.fill(
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014) // 3D depth perspective
                  ..rotateY(angle)
                  ..rotateZ(_cornerBias * (1.0 - absP) * kMaxCurlAngle),
                alignment: spineAlignment,
                child: isBackFacing
                    ? _buildPageBack(turningIndex, isRtl, absP)
                    : _buildPageFront(turningIndex, isRtl, absP),
              ),
            ),

            // 4. Subtle spine binding groove
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpineGroovePainter(isRtl: isRtl),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Backward Turn:
      // - Underneath page: _currentIndex
      // - Turning page: _currentIndex - 1 (rotates from -180 to 0 degrees onto the page)
      final underIndex = _currentIndex;
      final turningIndex = hasPrev ? _currentIndex - 1 : _currentIndex;

      final angle = (isRtl ? -1.0 : 1.0) * (1.0 - absP) * math.pi;
      final isBackFacing = (1.0 - absP) > 0.5;

      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Underneath current page
            Positioned.fill(
              child: RepaintBoundary(
                child: _opaquePage(underIndex),
              ),
            ),

            // 2. Cast shadow under incoming page
            Positioned.fill(
              child: CustomPaint(
                painter: _CastPageShadowPainter(
                  progress: 1.0 - absP,
                  isRtl: isRtl,
                ),
              ),
            ),

            // 3. Incoming 3D Bending Page
            Positioned.fill(
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateY(angle)
                  ..rotateZ(_cornerBias * absP * kMaxCurlAngle),
                alignment: spineAlignment,
                child: isBackFacing
                    ? _buildPageBack(turningIndex, isRtl, 1.0 - absP)
                    : _buildPageFront(turningIndex, isRtl, 1.0 - absP),
              ),
            ),

            // 4. Spine binding groove
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpineGroovePainter(isRtl: isRtl),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// Front of the manga page with realistic 3D curl lighting & fold highlight
  Widget _buildPageFront(int index, bool isRtl, double progress) {
    final spineAlign = isRtl ? Alignment.centerRight : Alignment.centerLeft;
    final edgeAlign = isRtl ? Alignment.centerLeft : Alignment.centerRight;

    return Stack(
      fit: StackFit.expand,
      children: [
        _opaquePage(index),
        // Dynamic paper curvature lighting: highlight on the crest, shadow in the fold
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: spineAlign,
                  end: edgeAlign,
                  colors: [
                    Colors.black.withValues(alpha: 0.35 * progress),
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.18 * progress),
                    Colors.black.withValues(alpha: 0.45 * progress),
                  ],
                  stops: const [0.0, 0.35, 0.82, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Back of the manga page showing authentic paper texture, lighting, and
  /// translucent ink bleed-through from the front.
  Widget _buildPageBack(int index, bool isRtl, double progress) {
    final spineAlign = isRtl ? Alignment.centerRight : Alignment.centerLeft;
    final edgeAlign = isRtl ? Alignment.centerLeft : Alignment.centerRight;

    return Transform(
      // Horizontally mirror the page so the back shows correctly
      transform: Matrix4.identity()..rotateY(math.pi),
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base paper color
          Container(color: const Color(0xFF18181A)),

          // Translucent reverse print of the manga artwork
          Opacity(
            opacity: 0.22,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFE2DFD8),
                BlendMode.srcATop,
              ),
              child: widget.itemBuilder(context, index),
            ),
          ),

          // Lighting on the back paper
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: edgeAlign,
                end: spineAlign,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.12),
                  const Color(0xFF141416),
                ],
                stops: const [0.0, 0.4, 0.85, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PAINTERS
// ============================================================================

/// Paints a soft drop shadow cast onto the underneath page as the top page lifts
class _CastPageShadowPainter extends CustomPainter {
  _CastPageShadowPainter({required this.progress, required this.isRtl});

  final double progress;
  final bool isRtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01 || progress >= 0.99) return;

    final w = size.width;
    final h = size.height;
    final opacity = (kShadowOpacity * math.sin(progress * math.pi)).clamp(0.0, 1.0);

    // Spine anchor
    final spineX = isRtl ? w : 0.0;
    final shadowWidth = w * 0.45 * math.sin(progress * math.pi);

    final rect = isRtl
        ? Rect.fromLTRB(spineX - shadowWidth, 0, spineX, h)
        : Rect.fromLTRB(spineX, 0, spineX + shadowWidth, h);

    final gradient = LinearGradient(
      begin: isRtl ? Alignment.centerLeft : Alignment.centerRight,
      end: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: opacity * 0.4),
        Colors.black.withValues(alpha: opacity),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_CastPageShadowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Paints the subtle dark book spine binding shadow at the center/spine edge
class _SpineGroovePainter extends CustomPainter {
  _SpineGroovePainter({required this.isRtl});

  final bool isRtl;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const grooveWidth = 14.0;

    final rect = isRtl
        ? Rect.fromLTRB(w - grooveWidth, 0, w, h)
        : const Rect.fromLTRB(0, 0, grooveWidth, 8000);

    final gradient = LinearGradient(
      begin: isRtl ? Alignment.centerLeft : Alignment.centerRight,
      end: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.35),
      ],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(Rect.fromLTRB(rect.left, 0, rect.right, h), paint);
  }

  @override
  bool shouldRepaint(_SpineGroovePainter oldDelegate) => false;
}
