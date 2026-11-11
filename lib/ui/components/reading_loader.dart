import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/series.dart';
import '../../services/page_cache.dart';
import '../../services/scrape/cf_session.dart';
import 'brand_logo.dart';

class ReadingStage {
  const ReadingStage({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;
}

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
      detail: 'Establishing secure connection to provider...',
      icon: Icons.public_rounded,
    ),
    ReadingStage(
      title: 'Bypassing bot security',
      detail: 'Negotiating Cloudflare clearance token...',
      icon: Icons.verified_user_rounded,
    ),
    ReadingStage(
      title: 'Stripping advertisements',
      detail: 'Removing banner scripts, video popups & trackers...',
      icon: Icons.shield_rounded,
    ),
    ReadingStage(
      title: 'Extracting chapter pages',
      detail: 'Scanning HTML structure and decoding image stream...',
      icon: Icons.auto_stories_rounded,
    ),
    ReadingStage(
      title: 'Preparing reader canvas',
      detail: 'Optimizing high-res panels for native reading...',
      icon: Icons.speed_rounded,
    ),
  ];

  @override
  State<ReadingLoader> createState() => _ReadingLoaderState();
}

class _ReadingLoaderState extends State<ReadingLoader>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  int _currentStageIndex = 0;
  Timer? _stageTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _startStageSimulation();
  }

  void _startStageSimulation() {
    // Progressively walk through the stages so the user sees live feedback
    // across the 2-6 seconds it typically takes to scrape/solve Cloudflare.
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (!mounted) return;
      if (_currentStageIndex < ReadingLoader.stages.length - 1) {
        setState(() {
          _currentStageIndex++;
        });
        _progressController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = ReadingLoader.stages[_currentStageIndex];
    final progress =
        (_currentStageIndex + 1) / ReadingLoader.stages.length;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Ambient soft backdrop of series cover
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

        // Deep vignette gradient overlay
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Color(0xC0090A0E),
                  Color(0xF5090A0E),
                  Color(0xFF090A0E),
                ],
                stops: [0.0, 0.65, 1.0],
                radius: 1.2,
              ),
            ),
          ),
        ),

        // Central Content Card
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Pulsing Beacon with Brand Mark
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.06);
                      final glowAlpha = 0.25 + (_pulseController.value * 0.2);

                      return Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00FFA3)
                                  .withValues(alpha: glowAlpha),
                              blurRadius: 36 * scale,
                              spreadRadius: 4 * scale,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: scale,
                            child: const BrandLogo(
                              size: 78,
                              withGlow: false,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Series Title & Chapter
                  Text(
                    widget.series.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),
                  if (widget.series.chapter.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.series.chapter,
                      style: const TextStyle(
                        color: Color(0xFF00FFA3),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // Stage Live Status Capsule Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00FFA3).withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Current Stage Icon & Title
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FFA3)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                stage.icon,
                                color: const Color(0xFF00FFA3),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 300),
                                    child: Text(
                                      widget.customStatus ?? stage.title,
                                      key: ValueKey(
                                        widget.customStatus ?? stage.title,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 300),
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
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00FFA3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            tween: Tween<double>(begin: 0.1, end: progress),
                            builder: (context, value, _) {
                              return LinearProgressIndicator(
                                value: value,
                                minHeight: 4,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00FFA3),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Stepper Dots Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            ReadingLoader.stages.length,
                            (index) {
                              final isDone = index < _currentStageIndex;
                              final isCurrent = index == _currentStageIndex;

                              Color dotColor;
                              if (isDone) {
                                dotColor = const Color(0xFF00FFA3);
                              } else if (isCurrent) {
                                dotColor = const Color(0xFF38BDF8);
                              } else {
                                dotColor = Colors.white24;
                              }

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: isCurrent ? 22 : 8,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: isCurrent
                                      ? [
                                          BoxShadow(
                                            color: dotColor.withValues(alpha: 0.5),
                                            blurRadius: 6,
                                          ),
                                        ]
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
