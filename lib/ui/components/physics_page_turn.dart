import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

// ============================================================================
// TUNABLE PHYSICS & VISUAL CONSTANTS
// ============================================================================
/// Spring stiffness for page settle animation. Higher = snappier snap.
const double kSpringStiffness = 420.0;

/// Spring damping. Higher = less oscillation/overshoot; lower = bouncier.
const double kSpringDamping = 34.0;

/// Mass of the sliding sheet.
const double kSpringMass = 1.0;

/// Fraction of screen width dragged to trigger page turn on slow release (0.0 - 1.0).
/// Kept low (0.16) so a light swipe or flick turns the page effortlessly without hard swiping.
const double kCompletionThreshold = 0.16;

/// Minimum fling velocity (pixels/second) to complete a turn regardless of distance.
/// Set to 180.0 so gentle flicks trigger the turn immediately.
const double kFlingVelocityThreshold = 180.0;

/// Rubber-band bounce distance factor when trying to turn past boundaries.
const double kRubberBandFactor = 0.16;

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

/// Ultra-smooth glass-morphism page turn with physics-based gesture tracking:
/// - Real-time finger following with momentum transfer via SpringSimulation.
/// - Top page scrolls away with a luminous frosted glass bevel, specular reflection & shadow.
/// - Underneath page is revealed directly below with subtle depth scaling & parallax.
/// - Zero polygon distortion; 100% crisp, readable manga artwork at 60fps.
/// - Velocity-modulated tactile audio feedback.
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
    final canTurn =
        forward ? (_currentIndex < widget.itemCount - 1) : (_currentIndex > 0);
    if (!canTurn) {
      _playRubberBand(forward: forward);
      return;
    }

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
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
      if (_currentIndex < widget.itemCount - 1) {
        _currentIndex++;
        widget.onPageChanged?.call(_currentIndex);
      }
    } else if (_targetProgress <= -0.9) {
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

    final isForward = rawProgress > 0;
    final canMove = isForward
        ? (_currentIndex < widget.itemCount - 1)
        : (_currentIndex > 0);

    if (!canMove) {
      final sign = rawProgress.sign;
      rawProgress = sign * math.pow(rawProgress.abs(), 0.6) * kRubberBandFactor;
    }

    // Play subtle peel rustle & vibration feedback when movement begins
    if (!_peelSoundPlayed && rawProgress.abs() >= 0.04 && canMove) {
      _peelSoundPlayed = true;
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
      widget.onPagePeel?.call(speed);
    }

    // Play page flip sound and subtle vibration as commitment threshold approaches
    if (!_flipSoundPlayed && rawProgress.abs() >= kCompletionThreshold && canMove) {
      _flipSoundPlayed = true;
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
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

    double target = 0.0;
    final absProg = _progress.abs();
    // Complete if dragged past completion threshold (0.16)
    if (absProg > kCompletionThreshold) {
      if (isForward) {
        target =
            normVelocity < -150.0 / size.width ? 0.0 : 1.0;
      } else {
        target =
            normVelocity > 150.0 / size.width ? 0.0 : -1.0;
      }
    } else {
      // Light flick / gentle swipe: effortlessly turns the page!
      if (normVelocity > kFlingVelocityThreshold / size.width) {
        target = 1.0;
      } else if (normVelocity < -kFlingVelocityThreshold / size.width) {
        target = -1.0;
      } else if (absProg > 0.06 &&
          ((isForward && normVelocity >= 0) || (!isForward && normVelocity <= 0))) {
        target = isForward ? 1.0 : -1.0;
      } else {
        target = 0.0;
      }
    }

    if (target != 0.0) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
      if (!_flipSoundPlayed) {
        _flipSoundPlayed = true;
        final flingSpeed = (normVelocity.abs() * 0.4).clamp(0.85, 1.55);
        widget.onPageTurnStart?.call(flingSpeed);
      }
    } else {
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
          return _buildGlassScrollTransition(size, hasNext, hasPrev);
        },
      ),
    );
  }

  Widget _opaquePage(int index) {
    return Container(
      color: Colors.black,
      child: widget.itemBuilder(context, index),
    );
  }

  /// Glass-like scroll-away reveal:
  /// The top manga sheet glides away with a glowing frosted edge, specular sheen,
  /// and drop shadow to reveal the page directly underneath with subtle depth scaling.
  Widget _buildGlassScrollTransition(Size size, bool hasNext, bool hasPrev) {
    final p = _progress.clamp(-1.2, 1.2);

    if (p == 0.0 && !_isDragging) {
      return RepaintBoundary(
        child: _opaquePage(_currentIndex),
      );
    }

    final isForward = p >= 0.0;
    final absP = p.abs().clamp(0.0, 1.0);
    final sign = widget.rtl ? -1.0 : 1.0;

    if (isForward) {
      // Forward Turn:
      // Underneath: _currentIndex + 1 (revealed directly below)
      // Top Glass Sheet: _currentIndex (slides smoothly away)
      final underIndex = hasNext ? _currentIndex + 1 : _currentIndex;
      final topIndex = _currentIndex;

      final slideOffset = -p * size.width * sign;
      final underScale = 0.95 + (0.05 * absP);
      final underParallax =
          (widget.rtl ? 1.0 : -1.0) * size.width * 0.10 * (1.0 - absP);
      final underDim = (1.0 - absP) * 0.30;

      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Underneath revealed page with subtle scale & parallax
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(underParallax, 0),
                child: Transform.scale(
                  scale: underScale,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(child: _opaquePage(underIndex)),
                      if (underDim > 0.01)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: underDim),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Sliding Glass Sheet (Current Page)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(slideOffset, 0),
                child: _buildGlassSheet(
                  topIndex,
                  size,
                  edgeOnRight: widget.rtl,
                  progress: absP,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Backward Turn:
      // Underneath: _currentIndex
      // Incoming Glass Sheet: _currentIndex - 1 (slides in over current page)
      final underIndex = _currentIndex;
      final topIndex = hasPrev ? _currentIndex - 1 : _currentIndex;

      final slideOffset = (widget.rtl ? 1.0 : -1.0) * size.width * (1.0 - absP);
      final underScale = 1.0 - (0.05 * absP);
      final underDim = absP * 0.30;

      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Underneath page (current page gently receding)
            Positioned.fill(
              child: Transform.scale(
                scale: underScale,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(child: _opaquePage(underIndex)),
                    if (underDim > 0.01)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: underDim),
                      ),
                  ],
                ),
              ),
            ),

            // 2. Incoming Glass Sheet (Previous Page)
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(slideOffset, 0),
                child: _buildGlassSheet(
                  topIndex,
                  size,
                  edgeOnRight: !widget.rtl,
                  progress: absP,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// Builds the glass pane with crisp content, glass bevel highlight, specular reflection and soft drop shadow.
  Widget _buildGlassSheet(
    int index,
    Size size, {
    required bool edgeOnRight,
    required double progress,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 28,
            spreadRadius: 4,
            offset: Offset(edgeOnRight ? 12 : -12, 0),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: Offset(edgeOnRight ? 4 : -4, 0),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Crisp manga content
          RepaintBoundary(child: _opaquePage(index)),

          // 1. Frosted glass bevel along the sliding edge
          Positioned(
            top: 0,
            bottom: 0,
            left: edgeOnRight ? null : 0,
            right: edgeOnRight ? 0 : null,
            child: IgnorePointer(
              child: Container(
                width: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: edgeOnRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: edgeOnRight
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.40),
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.02),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.25, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Crisp 1.5px glass edge specular line
          Positioned(
            top: 0,
            bottom: 0,
            left: edgeOnRight ? null : 0,
            right: edgeOnRight ? 0 : null,
            child: IgnorePointer(
              child: Container(
                width: 1.5,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),

          // 3. Dynamic glass surface reflection shifting with progress
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.08 * (1.0 - progress)),
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.04 * (1.0 - progress)),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
