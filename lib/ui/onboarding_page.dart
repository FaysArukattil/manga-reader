import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../theme/components/pressable_scale.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _onGetStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding_v2', true);

    if (!mounted) return;

    const Widget destination = AuthGate();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF090A0E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient soft radial gradient lighting
          Positioned(
            top: size.height * 0.12,
            left: size.width * 0.1,
            right: size.width * 0.1,
            height: size.height * 0.45,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00FFA3).withValues(alpha: 0.12),
                    const Color(0xFF0077B6).withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top 60%: Floating 3D Tilted Covers Showcase
                Expanded(
                  flex: 6,
                  child: AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, _) {
                      final floatVal = math.sin(_floatController.value * math.pi);
                      final dy = floatVal * 8.0;

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final h = constraints.maxHeight;
                          final cx = w / 2;
                          final cy = h / 2 + 10;

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Background Cover: Left Far (Thriller/Fantasy)
                              _FloatingBookCard(
                                x: cx - 145,
                                y: cy - 75 + dy * 0.7,
                                angle: -0.28,
                                width: 105,
                                height: 155,
                                title: 'WILD\nTHE\nMANY',
                                author: 'K. BRADLEY',
                                colorA: const Color(0xFFB45309),
                                colorB: const Color(0xFF78350F),
                                elevation: 8,
                              ),

                              // Background Cover: Right Far (Mystery/Horror)
                              _FloatingBookCard(
                                x: cx + 145,
                                y: cy - 65 - dy * 0.7,
                                angle: 0.26,
                                width: 110,
                                height: 160,
                                title: 'LAST\nNIGHT\nAT THE\nWEDDING',
                                author: 'J. REKULAK',
                                colorA: const Color(0xFFD97706),
                                colorB: const Color(0xFFB45309),
                                elevation: 8,
                              ),

                              // Lower Mid Left (Cyan/Blue Webtoon)
                              _FloatingBookCard(
                                x: cx - 95,
                                y: cy + 55 - dy * 0.5,
                                angle: -0.12,
                                width: 115,
                                height: 165,
                                title: 'SOLO\nLEVELING',
                                author: 'CHUGONG',
                                colorA: const Color(0xFF0284C7),
                                colorB: const Color(0xFF0F172A),
                                elevation: 12,
                              ),

                              // Lower Mid Right (Manga/Anime)
                              _FloatingBookCard(
                                x: cx + 95,
                                y: cy + 65 + dy * 0.5,
                                angle: 0.16,
                                width: 115,
                                height: 165,
                                title: 'ONE\nPIECE',
                                author: 'E. ODA',
                                colorA: const Color(0xFFDC2626),
                                colorB: const Color(0xFF450A0A),
                                elevation: 12,
                              ),

                              // Hero Center Top Cover: (Dark Emerald & Gold Masterpiece)
                              _FloatingBookCard(
                                x: cx,
                                y: cy - 40 - dy,
                                angle: 0.04,
                                width: 135,
                                height: 195,
                                title: 'THE\nRETURNED\nHUNTER',
                                author: 'BESTSELLER',
                                colorA: const Color(0xFF065F46),
                                colorB: const Color(0xFF042F2E),
                                isHero: true,
                                elevation: 22,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                // Bottom 40%: Typography & Call To Action
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          "Discover Stories\nYou'll Love",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your journey starts here. Track, bookmark, and\nread across every website with zero ads.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.45,
                          ),
                        ),
                        const Spacer(),

                        // Premium Pill Button "Let's get started >>"
                        PressableScale(
                          onTap: _onGetStarted,
                          scaleDown: 0.96,
                          child: Container(
                            height: 56,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0D2538),
                                  Color(0xFF071927),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              border: Border.all(
                                color: const Color(0xFF00FFA3)
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00FFA3)
                                      .withValues(alpha: 0.18),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Let's get started",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Color(0xFF00FFA3),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Color(0xFF00FFA3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingBookCard extends StatelessWidget {
  const _FloatingBookCard({
    required this.x,
    required this.y,
    required this.angle,
    required this.width,
    required this.height,
    required this.title,
    required this.author,
    required this.colorA,
    required this.colorB,
    this.isHero = false,
    this.elevation = 10,
  });

  final double x;
  final double y;
  final double angle;
  final double width;
  final double height;
  final String title;
  final String author;
  final Color colorA;
  final Color colorB;
  final bool isHero;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - width / 2,
      top: y - height / 2,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateZ(angle),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [colorA, colorB],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isHero
                  ? const Color(0xFF00FFA3).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.15),
              width: isHero ? 1.5 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: elevation,
                offset: Offset(0, elevation * 0.4),
              ),
              if (isHero)
                BoxShadow(
                  color: const Color(0xFF00FFA3).withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge or author at top
              Text(
                author,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: width * 0.075,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Title
              Text(
                title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width * 0.115,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              // Spine edge line indicator
              Container(
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  color: isHero ? const Color(0xFF00FFA3) : Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
