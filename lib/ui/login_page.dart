import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../blocs/auth_bloc.dart';
import '../theme/components/pressable_scale.dart';
import 'components/brand_logo.dart';

const _kBg = Color(0xFF07080C);
const _kMint = Color(0xFF00FFA3);

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
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 20),
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
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // Manga screentone fading out from the top-right corner
            const Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _ScreentonePainter()),
                ),
              ),
            ),

            SafeArea(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: const _Content(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child:
            Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const BrandLogo(size: 60, withGlow: false),
          const SizedBox(height: 28),
          const Text(
            'Pick up where\nyou left off.',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.08,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Sign in to keep your library and reading progress on every device. New here? Your account is created automatically.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.white54,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 32),
          const _GoogleButton(),
          const SizedBox(height: 18),
          Center(
            child: Text.rich(
              TextSpan(
                text: 'By continuing, you agree to our ',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.white38,
                  height: 1.45,
                ),
                children: [
                  TextSpan(
                    text: 'Terms of Service',
                    style: const TextStyle(
                      color: _kMint,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse(
                            'https://faysarukattil.github.io/manga-reader/terms.html',
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: _kMint,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse(
                            'https://faysarukattil.github.io/manga-reader/privacy.html',
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (a, b) => a.busy != b.busy,
      builder: (context, state) {
        return PressableScale(
          onTap: state.busy
              ? () {}
              : () => context.read<AuthBloc>().add(const AuthSignInRequested()),
          scaleDown: 0.98,
          child: Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: state.busy
                  ? const Center(
                      key: ValueKey('busy'),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF111216),
                          ),
                        ),
                      ),
                    )
                  : const Row(
                      key: ValueKey('idle'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GoogleGIcon(),
                        SizedBox(width: 12),
                        Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111216),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// SCREENTONE (static manga halftone, densest in the top-right corner)
// ===========================================================================
class _ScreentonePainter extends CustomPainter {
  const _ScreentonePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 13.0;
    final origin = Offset(size.width, 0);
    final reach = size.height * 0.55;
    final p = Paint()..isAntiAlias = true;
    var row = 0;
    for (double y = 0; y < reach; y += gap, row++) {
      final shift = row.isOdd ? gap / 2 : 0.0;
      for (double x = size.width + gap; x > -gap; x -= gap) {
        final px = x - shift;
        final d = (Offset(px, y) - origin).distance / reach;
        if (d >= 1) continue;
        final k = 1 - d;
        final r = 0.4 + 2.4 * k * k;
        p.color = Color.lerp(Colors.white, _kMint, 0.55)!
            .withValues(alpha: 0.04 + 0.09 * k);
        canvas.drawCircle(Offset(px, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// GOOGLE "G" (Official Multi-Color Identity Asset)
// ===========================================================================
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/google_logo.png',
      width: 22,
      height: 22,
      filterQuality: FilterQuality.high,
    );
  }
}
