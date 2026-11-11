import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import '../theme/components/pressable_scale.dart';
import 'components/brand_logo.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E2028),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090A0E),
        body: Stack(
          children: [
            // Top Ambient Lighting
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00FFA3).withValues(alpha: 0.15),
                      const Color(0xFF0077B6).withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Brand Logo Badge
                        const BrandLogo(size: 88, withGlow: true),
                        const SizedBox(height: 24),

                        // Title & Combined Intro
                        const Text(
                          'Welcome to Manga Reader',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Sign in or sign up with a single tap to sync your shelf, progress, and reading history across all your devices.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white60,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // High-converting Value Pillars Box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13151D),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                          child: const Column(
                            children: [
                              _PillarRow(
                                icon: Icons.bolt_rounded,
                                iconColor: Color(0xFF00FFA3),
                                title: 'Zero Ads & Clean Reading',
                                subtitle: 'Intrusive website ads and popups are automatically stripped.',
                              ),
                              SizedBox(height: 14),
                              _PillarRow(
                                icon: Icons.cloud_sync_rounded,
                                iconColor: Color(0xFF38BDF8),
                                title: 'Cloud Sync Everywhere',
                                subtitle: 'Your library and reading position stay backed up and synced.',
                              ),
                              SizedBox(height: 14),
                              _PillarRow(
                                icon: Icons.public_rounded,
                                iconColor: Color(0xFFA78BFA),
                                title: 'Universal Site Support',
                                subtitle: 'Read from any manga, manhwa, or webtoon source online.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Single Google Sign In / Sign Up Button
                        BlocBuilder<AuthBloc, AuthState>(
                          buildWhen: (a, b) => a.busy != b.busy,
                          builder: (context, state) {
                            return PressableScale(
                              onTap: state.busy
                                  ? () {}
                                  : () => context.read<AuthBloc>().add(
                                        const AuthSignInRequested(),
                                      ),
                              scaleDown: 0.97,
                              child: Container(
                                height: 54,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: state.busy
                                    ? const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Color(0xFF111216),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _GoogleGIcon(),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'Continue with Google',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF111216),
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),

                        // Guest / Skip Option
                        TextButton(
                          onPressed: () => context
                              .read<AuthBloc>()
                              .add(const AuthSignInGuestRequested()),
                          child: const Text(
                            'Explore as Guest without signing in →',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Terms note
                        const Text(
                          'By continuing, you agree to Manga Reader\'s Terms and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white30,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarRow extends StatelessWidget {
  const _PillarRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoogleGIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width / 2;

    final paintRed = Paint()..color = const Color(0xFFEA4335);
    final paintYellow = Paint()..color = const Color(0xFFFBBC05);
    final paintGreen = Paint()..color = const Color(0xFF34A853);
    final paintBlue = Paint()..color = const Color(0xFF4285F4);

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    final strokeW = size.width * 0.22;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW;

    strokePaint.color = paintRed.color;
    canvas.drawArc(rect.deflate(strokeW / 2), -0.7, 1.4, false, strokePaint);

    strokePaint.color = paintYellow.color;
    canvas.drawArc(rect.deflate(strokeW / 2), 0.7, 1.3, false, strokePaint);

    strokePaint.color = paintGreen.color;
    canvas.drawArc(rect.deflate(strokeW / 2), 2.0, 1.3, false, strokePaint);

    strokePaint.color = paintBlue.color;
    canvas.drawArc(rect.deflate(strokeW / 2), 3.3, 1.8, false, strokePaint);

    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(cx - 1, cy - strokeW / 2, r + 1, strokeW),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
