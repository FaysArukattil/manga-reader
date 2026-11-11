import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/series.dart';
import '../../services/page_cache.dart';
import '../../services/scrape/cf_session.dart';

// ===========================================================================
// PALETTE
// ===========================================================================
const _kMint = Color(0xFF00FFA3);
const _kCyan = Color(0xFF00B4D8);
const _kPaper = Color(0xFFF7F3EA);
const _kPaperShade = Color(0xFFDDD5C4);
const _kInk = Color(0xFF14110F);
const _kCoverDark = Color(0xFF090E17);
const _kCoverLight = Color(0xFF192538);

double _seg(double s, double a, double b, [Curve c = Curves.linear]) {
  if (s <= a) return 0;
  if (s >= b) return 1;
  return c.transform((s - a) / (b - a));
}

// ===========================================================================
// READING STAGE MODEL
// ===========================================================================
class ReadingStage {
  const ReadingStage({
    required this.title,
    required this.detail,
    required this.icon,
    this.tag = '',
  });

  final String title;
  final String detail;
  final IconData icon;
  final String tag;
}

// ===========================================================================
// READING LOADER
// ===========================================================================
class ReadingLoader extends StatefulWidget {
  const ReadingLoader({
    super.key,
    required this.series,
    this.customStatus,
  });

  final Series series;
  final String? customStatus;

  static const List<ReadingStage> stages = [
    ReadingStage(
      title: 'Connecting to source',
      detail: 'Establishing high-speed pipeline to host...',
      icon: Icons.wifi_tethering_rounded,
      tag: '01 / CONNECT',
    ),
    ReadingStage(
      title: 'Bypassing bot security',
      detail: 'Negotiating clearance & certificate handshake...',
      icon: Icons.verified_user_rounded,
      tag: '02 / CLEARANCE',
    ),
    ReadingStage(
      title: 'Stripping advertisements',
      detail: 'Purifying layout & removing ad scripts...',
      icon: Icons.auto_awesome_rounded,
      tag: '03 / PURIFY',
    ),
    ReadingStage(
      title: 'Extracting chapter pages',
      detail: 'Decoding high-definition panel image stream...',
      icon: Icons.auto_stories_rounded,
      tag: '04 / EXTRACT',
    ),
    ReadingStage(
      title: 'Preparing reader canvas',
      detail: 'Optimizing interactive high-res page view...',
      icon: Icons.speed_rounded,
      tag: '05 / READY',
    ),
  ];

  @override
  State<ReadingLoader> createState() => _ReadingLoaderState();
}

class _ReadingLoaderState extends State<ReadingLoader>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _progressController;
  late Animation<double> _progressAnimation;

  int _currentStageIndex = 0;
  Timer? _stageTimer;

  // Timings for stage simulation:
  // Stage 0: 700ms -> switches to 1
  // Stage 1: 1100ms -> switches to 2 (total 1800ms, so at 1500ms stage 1 is active)
  // Stage 2: 1100ms -> switches to 3
  // Stage 3: 1100ms -> switches to 4
  static const _durations = [700, 1100, 1100, 1100];

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _progressAnimation = Tween<double>(
      begin: 0.12,
      end: 0.20,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    ));

    _scheduleNextStage();
  }

  void _scheduleNextStage() {
    if (_currentStageIndex >= ReadingLoader.stages.length - 1) return;

    final delay = _durations[_currentStageIndex];
    _stageTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _currentStageIndex++;
      });

      final targetProgress =
          (_currentStageIndex + 1) / ReadingLoader.stages.length;
      final currentProgress = _progressAnimation.value;

      _progressAnimation = Tween<double>(
        begin: currentProgress,
        end: targetProgress,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeOutCubic,
      ));

      _progressController.forward(from: 0.0);
      _scheduleNextStage();
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _ambientController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = ReadingLoader.stages[_currentStageIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cover Artwork Ambient Background
          if (widget.series.coverUrl != null &&
              widget.series.coverUrl!.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.22,
                child: CachedNetworkImage(
                  imageUrl: widget.series.coverUrl!,
                  cacheKey: widget.series.coverUrl!,
                  cacheManager: PageCache.instance,
                  httpHeaders: CfSession.imageHeaders(
                    widget.series.coverUrl!,
                    widget.series.url.isNotEmpty ? widget.series.url : null,
                  ),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // 2. Halftone & Vignette Overlay
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.15),
                    radius: 1.1,
                    colors: [
                      Color(0x7007080C),
                      Color(0xDD07080C),
                      Color(0xFF07080C),
                    ],
                    stops: [0.0, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Central Canvas
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                        [_ambientController, _progressController]),
                    builder: (context, _) {
                      final progress = _progressAnimation.value;
                      final t = _ambientController.value * 4.0; // seconds

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Category/Engine Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kMint.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _kMint.withValues(alpha: 0.28),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: _kMint,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: _kMint,
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'PREPARING CHAPTER',
                                  style: TextStyle(
                                    color: _kMint,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Series Title
                          Text(
                            widget.series.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.25,
                            ),
                          ),
                          if (widget.series.chapter.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.series.chapter,
                              style: const TextStyle(
                                color: _kMint,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),

                          // 3D Unfolding Book Animation Showcase
                          SizedBox(
                            width: 280,
                            height: 190,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _UnfoldingBookPainter(
                                      progress: progress,
                                      time: t,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Progress percentage & step count
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                stage.tag.isNotEmpty
                                    ? stage.tag
                                    : 'STEP ${_currentStageIndex + 1} OF ${ReadingLoader.stages.length}',
                                style: TextStyle(
                                  color: _kMint.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '${(progress * 100).toInt()}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const Text(
                                    '%',
                                    style: TextStyle(
                                      color: _kMint,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Animated Progress Bar
                          Container(
                            width: double.infinity,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress.clamp(0.02, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: const LinearGradient(
                                    colors: [_kCyan, _kMint],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _kMint.withValues(alpha: 0.55),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Live Stage Status Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10131B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _kMint.withValues(alpha: 0.22),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _kMint.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _kMint.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    stage.icon,
                                    color: _kMint,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        child: Text(
                                          widget.customStatus ?? stage.title,
                                          key: ValueKey(
                                              widget.customStatus ??
                                                  stage.title),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        child: Text(
                                          stage.detail,
                                          key: ValueKey(stage.detail),
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            _kMint),
                                    backgroundColor:
                                        _kMint.withValues(alpha: 0.15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 5-Stage Stepper Pills
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              ReadingLoader.stages.length,
                              (index) {
                                final isDone = index < _currentStageIndex;
                                final isCurrent = index == _currentStageIndex;

                                Color pillColor;
                                if (isDone) {
                                  pillColor = _kMint;
                                } else if (isCurrent) {
                                  pillColor = _kCyan;
                                } else {
                                  pillColor = Colors.white.withValues(alpha: 0.14);
                                }

                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: index ==
                                              ReadingLoader.stages.length - 1
                                          ? 0
                                          : 6,
                                    ),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      height: isCurrent ? 5.5 : 4,
                                      decoration: BoxDecoration(
                                        color: pillColor,
                                        borderRadius: BorderRadius.circular(3),
                                        boxShadow: isCurrent || isDone
                                            ? [
                                                BoxShadow(
                                                  color: pillColor.withValues(
                                                      alpha: isCurrent ? 0.6 : 0.3),
                                                  blurRadius: 6,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
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

// ===========================================================================
// 3D UNFOLDING MANGA BOOK PAINTER
// ===========================================================================
const _kLayouts = <List<List<double>>>[
  [
    [0.0, 0.0, 1.0, 0.36],
    [0.0, 0.39, 0.48, 0.30],
    [0.52, 0.39, 0.48, 0.30],
    [0.0, 0.72, 1.0, 0.28],
  ],
  [
    [0.0, 0.0, 0.56, 0.48],
    [0.59, 0.0, 0.41, 0.48],
    [0.0, 0.51, 1.0, 0.22],
    [0.0, 0.76, 1.0, 0.24],
  ],
  [
    [0.0, 0.0, 1.0, 0.24],
    [0.0, 0.27, 0.34, 0.46],
    [0.37, 0.27, 0.63, 0.46],
    [0.0, 0.76, 1.0, 0.24],
  ],
];

class _UnfoldingBookPainter extends CustomPainter {
  _UnfoldingBookPainter({
    required this.progress,
    required this.time,
  });

  final double progress;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.52;
    const halfW = 82.0;
    const bookH = 112.0;

    // Gentle breathing elevation bob
    final bob = math.sin(time * 2.6) * 3.2;
    final center = Offset(cx, cy + bob);

    // Dynamic rotation angles driven by progress
    final openCover = _seg(progress, 0.04, 0.32, Curves.easeInOutCubic);
    final openLeaf1 = _seg(progress, 0.25, 0.54, Curves.easeInOutSine);
    final openLeaf2 = _seg(progress, 0.50, 0.76, Curves.easeInOutSine);
    final openLeaf3 = _seg(progress, 0.72, 0.94, Curves.easeInOutSine);

    final coverAngle = math.pi * openCover;
    final leaf1Angle = math.pi * openLeaf1;
    final leaf2Angle = math.pi * openLeaf2;
    final leaf3Angle = math.pi * openLeaf3;

    // Camera shift to center the book as it unfolds
    final shiftX = -halfW / 2 * (1.0 - openCover);

    canvas.save();
    canvas.translate(center.dx + shiftX, center.dy);

    // 1. Ambient Glow behind the book
    if (openCover > 0.02) {
      final glowPulse = 0.88 + 0.12 * math.sin(time * 3.4);
      canvas.drawCircle(
        const Offset(0, -10),
        halfW * 1.6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _kMint.withValues(alpha: (0.24 * openCover * glowPulse).clamp(0.0, 0.5)),
              _kCyan.withValues(alpha: (0.12 * openCover * glowPulse).clamp(0.0, 0.3)),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(
            Rect.fromCircle(center: const Offset(0, -10), radius: halfW * 1.6),
          ),
      );
    }

    // 2. Dynamic Ground Shadow
    final shadowWidth = halfW * (1.1 + openCover * 0.95);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-shiftX, bookH / 2 + 16),
        width: shadowWidth,
        height: 18,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // 3. Back Board (Hardcover Base)
    final board = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-2, -bookH / 2 - 3, halfW + 3, bookH / 2 + 3),
      const Radius.circular(7),
    );
    canvas.drawRRect(board, Paint()..color = _kCoverDark);
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _kMint.withValues(alpha: 0.4),
    );

    // 4. Page block edge on the right
    const pageRect = Rect.fromLTWH(0, -bookH / 2 + 4, halfW - 4, bookH - 8);
    for (var i = 3; i >= 1; i--) {
      canvas.drawRect(
        pageRect.shift(Offset(i * 1.2, 0)),
        Paint()..color = _kPaperShade,
      );
    }
    _drawPaperFace(canvas, pageRect, 1, true, halfW, bookH);

    // 5. Leaves rendering with 3D perspective & depth-sorted overlap
    final angles = [coverAngle, leaf1Angle, leaf2Angle, leaf3Angle];

    // Right-side leaves (facing right)
    final rightSide = [
      for (var i = 0; i < 4; i++)
        if (angles[i] <= math.pi / 2) i,
    ];
    for (final i in rightSide.reversed) {
      _drawLeaf(canvas, i, angles[i], halfW, bookH);
    }

    // Left-side leaves (swung over to left)
    for (var i = 0; i < 4; i++) {
      if (angles[i] > math.pi / 2) {
        _drawLeaf(canvas, i, angles[i], halfW, bookH);
      }
    }

    // 6. Spine Crease Shadow
    if (openCover > 0.02) {
      const crease = Rect.fromLTRB(-12, -bookH / 2, 12, bookH / 2);
      canvas.drawRect(
        crease,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.42 * openCover),
              Colors.transparent,
            ],
          ).createShader(crease),
      );
    }

    // 7. Light Beam rising from spine gutter
    if (openCover > 0.15) {
      final beamP = _seg(progress, 0.25, 0.95, Curves.easeOut);
      final beamPulse = 0.88 + 0.12 * math.sin(time * 3.8);
      final beamPath = Path()
        ..moveTo(-halfW * 0.25, 0)
        ..lineTo(-halfW * 0.75, -bookH * 1.2)
        ..lineTo(halfW * 0.75, -bookH * 1.2)
        ..lineTo(halfW * 0.25, 0)
        ..close();

      canvas.drawPath(
        beamPath,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              _kMint.withValues(alpha: (0.35 * beamP * beamPulse).clamp(0.0, 0.6)),
              Colors.transparent,
            ],
          ).createShader(
            const Rect.fromLTRB(-halfW, -bookH * 1.2, halfW, 0),
          ),
      );
    }

    // 8. Rising Particles / Sparks
    _drawParticles(canvas, halfW, bookH, time, progress);

    canvas.restore();
  }

  void _drawLeaf(Canvas canvas, int i, double a, double halfW, double bookH) {
    final isCover = i == 0;
    final rect = isCover
        ? Rect.fromLTWH(0, -bookH / 2, halfW, bookH)
        : Rect.fromLTWH(0, -bookH / 2 + 4, halfW - 4, bookH - 8);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(isCover ? 7 : 3));

    // Subtle flutter for currently moving page
    final flutter = (i > 0 && a > 0.05 && a < math.pi * 0.95)
        ? math.sin(time * 6.0 + i) * 0.025
        : 0.0;

    canvas.save();
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0013)
      ..rotateY(a + flutter);
    canvas.transform(m.storage);

    final back = a > math.pi / 2;
    if (back) {
      canvas.translate(rect.right, 0);
      canvas.scale(-1.0, 1.0);
    }
    canvas.clipRRect(rrect, doAntiAlias: true);

    if (isCover) {
      back
          ? _drawCoverBack(canvas, rect, halfW)
          : _drawCoverFront(canvas, rect, halfW);
    } else {
      _drawPaperFace(
        canvas,
        rect,
        back ? (i * 2 + 1) % 3 : (i * 2) % 3,
        !back,
        halfW,
        bookH,
      );
    }

    // Dynamic page shadow gradient during rotation
    final sh = math.sin(a);
    if (sh > 0.01) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.04 * sh),
              Colors.black.withValues(alpha: 0.38 * sh),
            ],
          ).createShader(rect),
      );
    }

    canvas.restore();
  }

  void _drawCoverFront(Canvas canvas, Rect r, double halfW) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCoverLight, _kCoverDark],
        ).createShader(r),
    );

    // Mint Diagonal Accent Slash
    final y1 = r.top + r.height * 0.65;
    final y2 = r.top + r.height * 0.40;
    canvas.drawPath(
      Path()
        ..moveTo(r.left, y1)
        ..lineTo(r.right, y2)
        ..lineTo(r.right, y2 + 10)
        ..lineTo(r.left, y1 + 10)
        ..close(),
      Paint()..color = _kMint.withValues(alpha: 0.85),
    );

    // Inner embossed border
    canvas.drawRect(
      r.deflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _kMint.withValues(alpha: 0.45),
    );

    // Cover Typography
    final tpManga = TextPainter(
      text: TextSpan(
        text: 'MANGA',
        style: TextStyle(
          color: Colors.white,
          fontSize: halfW * 0.17,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpManga.paint(canvas, Offset(r.left + 14, r.top + 16));

    final tpReader = TextPainter(
      text: TextSpan(
        text: 'READER',
        style: TextStyle(
          color: _kMint,
          fontSize: halfW * 0.09,
          fontWeight: FontWeight.w800,
          letterSpacing: 3.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpReader.paint(canvas, Offset(r.left + 15, r.top + 16 + halfW * 0.20));

    final tpVol = TextPainter(
      text: TextSpan(
        text: 'VOL. 01',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: halfW * 0.08,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpVol.paint(canvas, Offset(r.right - 14 - tpVol.width, r.bottom - 20));

    // Spine hinge shading
    final hinge = Rect.fromLTWH(r.left, r.top, 10, r.height);
    canvas.drawRect(
      hinge,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ).createShader(hinge),
    );
  }

  void _drawCoverBack(Canvas canvas, Rect r, double halfW) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF0C121A));
    canvas.drawRect(
      r.deflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = _kMint.withValues(alpha: 0.25),
    );

    final tp = TextPainter(
      text: const TextSpan(
        text: 'SHELFMARK',
        style: TextStyle(
          color: _kMint,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawPaperFace(Canvas canvas, Rect rect, int layoutIdx, bool spineLeft,
      double halfW, double bookH) {
    canvas.drawRect(rect, Paint()..color = _kPaper);

    final inner = Rect.fromLTRB(
      rect.left + (spineLeft ? 12 : 7),
      rect.top + 8,
      rect.right - (spineLeft ? 7 : 12),
      rect.bottom - 8,
    );

    final layout = _kLayouts[layoutIdx % _kLayouts.length];
    final pFill = Paint()..color = const Color(0xFFEBE3D3);
    final pBorder = Paint()
      ..color = _kInk.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final b in layout) {
      final pr = Rect.fromLTWH(
        inner.left + b[0] * inner.width,
        inner.top + b[1] * inner.height,
        b[2] * inner.width - 2,
        b[3] * inner.height - 2,
      );

      canvas.drawRect(pr, pFill);
      canvas.drawRect(pr, pBorder);

      // Subtle screentone lines
      final linePaint = Paint()
        ..color = _kInk.withValues(alpha: 0.12)
        ..strokeWidth = 0.8;
      for (double y = pr.top + 4; y < pr.bottom - 3; y += 4) {
        canvas.drawLine(
          Offset(pr.left + 3, y),
          Offset(pr.right - 3, y),
          linePaint,
        );
      }
    }

    // Spine gutter shadow
    final gutter = Rect.fromLTWH(
      spineLeft ? rect.left : rect.right - 8,
      rect.top,
      8,
      rect.height,
    );
    canvas.drawRect(
      gutter,
      Paint()
        ..shader = LinearGradient(
          colors: spineLeft
              ? [Colors.black.withValues(alpha: 0.22), Colors.transparent]
              : [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
        ).createShader(gutter),
    );
  }

  void _drawParticles(Canvas canvas, double halfW, double bookH, double t,
      double progress) {
    if (progress < 0.2) return;
    final paint = Paint()..isAntiAlias = true;

    for (var i = 0; i < 14; i++) {
      final pTime = (t * 0.8 + i * 0.45) % 2.5;
      final frac = pTime / 2.5;
      final alpha = (1.0 - frac).clamp(0.0, 1.0);

      final seedX = math.sin(i * 13.5) * halfW * 0.85;
      final seedY = -frac * bookH * 0.95;
      final rot = (i * 2.0 + t * 2.5);

      canvas.save();
      canvas.translate(seedX, seedY);
      canvas.rotate(rot);

      if (i % 2 == 0) {
        paint
          ..style = PaintingStyle.fill
          ..color = _kPaper.withValues(alpha: 0.85 * alpha);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: 4.5, height: 6.5),
            const Radius.circular(1.0),
          ),
          paint,
        );
      } else {
        paint
          ..style = PaintingStyle.fill
          ..color = _kMint.withValues(alpha: 0.95 * alpha);
        // Star particle
        final path = Path()
          ..moveTo(0, -3.5)
          ..quadraticBezierTo(0, 0, 3.5, 0)
          ..quadraticBezierTo(0, 0, 0, 3.5)
          ..quadraticBezierTo(0, 0, -3.5, 0)
          ..quadraticBezierTo(0, 0, 0, -3.5)
          ..close();
        canvas.drawPath(path, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _UnfoldingBookPainter old) =>
      old.progress != progress || old.time != time;
}
