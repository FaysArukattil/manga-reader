import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import 'components/brand_logo.dart';
import 'onboarding_page.dart';

// ===========================================================================
// PALETTE (matches onboarding)
// ===========================================================================
const _kBg = Color(0xFF07080C);
const _kMint = Color(0xFF00FFA3);
const _kCyan = Color(0xFF00B4D8);
const _kPaper = Color(0xFFF4EFE6);
const _kPaperShade = Color(0xFFD9D1C0);
const _kInk = Color(0xFF14110F);

// ===========================================================================
// TIMELINE  (all values are SECONDS, so tuning is easy)
//
//   0.00-0.40  book pops in
//   0.12-0.62  cover swings open
//   0.55-1.15  three manga pages riffle over (evenly staggered)
//   1.20       IMPACT: flash, shake, speed-line burst, logo erupts, BOOM!!
//   1.50-2.10  title letters slam in, brush slash, tagline
//   2.10-3.50  the logo "hero hold": floating logo, twinkles, light beam,
//              pulsing glow, ambient speed lines
//   3.50+0.40  short beat, then continue to the app
// ===========================================================================
const _kDur = 3.5;
const _kHoldMs = 400;
const _kImpact = 1.2;

double _seg(double s, double a, double b, [Curve c = Curves.linear]) {
  if (s <= a) return 0;
  if (s >= b) return 1;
  return c.transform((s - a) / (b - a));
}

// ===========================================================================
// PAGE
// ===========================================================================
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _halftoneFade;
  bool _hit = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_kDur * 1000).round()),
    );
    _halftoneFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );
    _c.addListener(() {
      if (!_hit && _c.value * _kDur >= _kImpact) {
        _hit = true;
        HapticFeedback.mediumImpact();
      }
    });
    _c.forward().then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: _kHoldMs));
      _proceed();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    if (!mounted || _navigating) return;
    _navigating = true;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('seen_onboarding_v2') ?? false;

    if (!mounted) return;

    final destination =
        hasSeenOnboarding ? const AuthGate() : const OnboardingPage();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _proceed, // tap anywhere to skip
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              opacity: _halftoneFade,
              child: const RepaintBoundary(
                child: CustomPaint(painter: _HalftoneBgPainter()),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.1),
                      radius: 0.95,
                      colors: [Color(0x00000000), Color(0xCC07080C)],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) =>
                    _buildScene(box.maxWidth, box.maxHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScene(double w, double h) {
    final s = _c.value * _kDur;

    final cx = w / 2;
    final cy = h * 0.47;
    final bookW = math.min(w * 0.74, 320.0);
    final halfW = bookW / 2;
    final bookH = halfW * 1.3;
    final center = Offset(cx, cy);

    // Impact shake (smooth exponential decay)
    final since = s - _kImpact;
    final shakeAmp = since > 0 ? math.exp(-since * 9) * 5.5 : 0.0;
    final shake = Offset(
      math.sin(s * 60) * shakeAmp,
      math.cos(s * 51) * shakeAmp * 0.8,
    );

    // Flash
    double flash = 0;
    if (s >= _kImpact - 0.04 && s < _kImpact) {
      flash = (s - (_kImpact - 0.04)) / 0.04;
    } else if (s >= _kImpact) {
      flash = 1 - _seg(s, _kImpact, _kImpact + 0.3, Curves.easeOut);
    }

    // Logo
    final logoTravel = _seg(s, _kImpact, _kImpact + 0.5, Curves.easeOutCubic);
    final logoPop = _seg(s, _kImpact, _kImpact + 0.5, Curves.easeOutBack);
    final logoOpacity = _seg(s, _kImpact, _kImpact + 0.12);
    final logoFinalY = cy - bookH / 2 - 56;
    final holdFloat = _seg(s, _kImpact + 0.5, _kImpact + 0.9);
    final logoY = (cy - 10) +
        (logoFinalY - (cy - 10)) * logoTravel +
        math.sin(s * 2.4) * 3.5 * holdFloat;
    final breathe = 1 + 0.018 * math.sin(s * 3.2) * holdFloat;

    // Glow (grows, spikes on impact, then keeps pulsing softly)
    final glow = _seg(s, 0.2, 1.2, Curves.easeInOut);
    final glowBoost = 1 +
        0.5 * (since > 0 ? math.exp(-since * 6) : 0) +
        0.10 * math.sin(s * 3.0) * _seg(s, _kImpact + 0.5, _kImpact + 1.0);

    // SFX
    final rumble = _seg(s, 0.10, 0.30) * (1 - _seg(s, 0.85, 1.10));
    final stamp = _seg(s, _kImpact + 0.02, _kImpact + 0.28, Curves.easeOutBack);
    final stampOpacity = _seg(s, _kImpact + 0.02, _kImpact + 0.12);

    return Transform.translate(
      offset: shake,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ambient glow
            Positioned(
              left: cx - 260,
              top: cy - 260,
              width: 520,
              height: 520,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _kMint.withValues(
                            alpha: (0.20 * glow * glowBoost).clamp(0.0, 0.6)),
                        _kCyan.withValues(
                            alpha: (0.10 * glow * glowBoost).clamp(0.0, 0.4)),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Speed lines
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpeedLinesPainter(center: center, s: s),
                ),
              ),
            ),

            // Manga panel frame
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter:
                      _PanelFramePainter(_seg(s, 0.0, 0.9, Curves.easeOut)),
                ),
              ),
            ),

            // RUMBLE SFX while the book opens
            if (rumble > 0.01)
              Positioned(
                left: 24 + math.sin(s * 40) * 1.6,
                top: cy - bookH / 2 - 26 + math.cos(s * 33) * 1.6,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: rumble,
                    child: Transform.rotate(
                      angle: -0.14,
                      child: _Sfx(
                        'RUMBLE',
                        20,
                        Colors.white.withValues(alpha: 0.92),
                        _kMint.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),

            // The book
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BookPainter(
                    s: s,
                    center: center,
                    halfW: halfW,
                    h: bookH,
                  ),
                ),
              ),
            ),

            // Paper bits, sparkles, twinkles
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SparkPainter(
                    origin: Offset(cx, cy - 8),
                    twinkleCenter: Offset(cx, logoFinalY),
                    s: s,
                  ),
                ),
              ),
            ),

            // Logo
            if (logoOpacity > 0)
              Positioned(
                left: cx - 60,
                top: logoY - 60,
                width: 120,
                height: 120,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: logoOpacity,
                    child: Transform.scale(
                      scale: (logoPop * breathe).clamp(0.0, 1.3),
                      child: const Center(
                        child: BrandLogo(size: 84, withGlow: true),
                      ),
                    ),
                  ),
                ),
              ),

            // BOOM!! impact stamp
            if (stampOpacity > 0)
              Positioned(
                right: 20,
                top: cy - bookH / 2 - 36,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: stampOpacity * (1 - 0.35 * _seg(s, 2.2, 3.0)),
                    child: Transform.rotate(
                      angle: 0.2,
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * stamp + (1 - stamp) * 1.2,
                        child: const _Sfx(
                          'BOOM!!',
                          30,
                          Colors.white,
                          _kMint,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Title block
            Positioned(
              left: 0,
              right: 0,
              top: cy + bookH / 2 + 34,
              child: IgnorePointer(child: _buildTitle(s, w)),
            ),

            // Bottom chapter loader
            Positioned(
              bottom: 44,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _buildLoader(s)),
            ),

            // Impact flash
            if (flash > 0.001)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color.lerp(_kMint, Colors.white, 0.6)!
                        .withValues(alpha: 0.18 * flash),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(double s, double w) {
    const title = 'MANGA READER';
    final tagOpacity = _seg(s, _kImpact + 0.25, _kImpact + 0.50);
    final slash =
        _seg(s, _kImpact + 0.75, _kImpact + 1.05, Curves.easeOutCubic);
    final sub = _seg(s, _kImpact + 0.85, _kImpact + 1.25, Curves.easeOut);

    final letters = <Widget>[];
    for (var i = 0; i < title.length; i++) {
      final start = _kImpact + 0.30 + i * 0.025;
      final p = _seg(s, start, start + 0.30, Curves.easeOutCubic);
      letters.add(
        Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, (1 - p) * 16),
            child: Text(
              title[i],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.0,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: tagOpacity,
          child: Text(
            'YOUR STORY BEGINS',
            style: TextStyle(
              color: _kMint.withValues(alpha: 0.85),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: w * 0.9,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Color(0xFFE2E8F0), _kMint],
                stops: [0.0, 0.7, 1.0],
              ).createShader(bounds),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: letters,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 140,
          height: 9,
          child: CustomPaint(painter: _BrushSlashPainter(slash)),
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: sub,
          child: Transform.translate(
            offset: Offset(0, (1 - sub) * 6),
            child: const Text(
              'All your stories. Pure reading.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoader(double s) {
    final o = _seg(s, 0.4, 0.9);
    final progress = (s / _kDur).clamp(0.0, 1.0);
    return Opacity(
      opacity: o,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CHAPTER 01',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 120,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kCyan, _kMint]),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: _kMint.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
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
// SFX TEXT (outlined comic sound effect)
// ===========================================================================
class _Sfx extends StatelessWidget {
  const _Sfx(this.text, this.size, this.fill, this.outline);

  final String text;
  final double size;
  final Color fill;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.18
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 1,
            color: fill,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// HALFTONE (static screentone, bigger dots toward the edges)
// ===========================================================================
class _HalftoneBgPainter extends CustomPainter {
  const _HalftoneBgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 14.0;
    final cx = size.width / 2;
    final cy = size.height * 0.47;
    final maxD = math.sqrt(cx * cx + size.height * size.height * 0.28);
    final p = Paint()..isAntiAlias = true;
    var row = 0;
    for (double y = 0; y < size.height + gap; y += gap, row++) {
      final shift = row.isOdd ? gap / 2 : 0.0;
      for (double x = 0; x < size.width + gap; x += gap) {
        final px = x + shift;
        final dx = px - cx;
        final dy = y - cy;
        final d = (math.sqrt(dx * dx + dy * dy) / maxD).clamp(0.0, 1.0);
        final sc = ((d - 0.3) / 0.7).clamp(0.0, 1.0);
        if (sc <= 0.0) continue;
        final r = 0.4 + 2.6 * sc * sc;
        final mintMix = (y / size.height).clamp(0.0, 1.0);
        p.color = Color.lerp(Colors.white, _kMint, mintMix * 0.7)!
            .withValues(alpha: 0.05 + 0.06 * sc);
        canvas.drawCircle(Offset(px, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// PANEL FRAME (manga page border drawing itself in)
// ===========================================================================
class _PanelFramePainter extends CustomPainter {
  _PanelFramePainter(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0) return;
    const inset = 14.0;
    final r = Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.square;

    final e0 = (p * 4).clamp(0.0, 1.0);
    final e1 = (p * 4 - 1).clamp(0.0, 1.0);
    final e2 = (p * 4 - 2).clamp(0.0, 1.0);
    final e3 = (p * 4 - 3).clamp(0.0, 1.0);

    Offset lerp(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;
    canvas.drawLine(r.topLeft, lerp(r.topLeft, r.topRight, e0), line);
    canvas.drawLine(r.topRight, lerp(r.topRight, r.bottomRight, e1), line);
    canvas.drawLine(r.bottomRight, lerp(r.bottomRight, r.bottomLeft, e2), line);
    canvas.drawLine(r.bottomLeft, lerp(r.bottomLeft, r.topLeft, e3), line);

    final br = Paint()
      ..color = _kMint.withValues(alpha: 0.85 * p)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final l = 20.0 * p;
    canvas.drawLine(r.topLeft, r.topLeft + Offset(l, 0), br);
    canvas.drawLine(r.topLeft, r.topLeft + Offset(0, l), br);
    canvas.drawLine(r.bottomRight, r.bottomRight + Offset(-l, 0), br);
    canvas.drawLine(r.bottomRight, r.bottomRight + Offset(0, -l), br);
  }

  @override
  bool shouldRepaint(covariant _PanelFramePainter old) => old.p != p;
}

// ===========================================================================
// SPEED LINES (tapered manga focus lines)
// ===========================================================================
class _Ray {
  const _Ray(this.angle, this.inner, this.len, this.width);
  final double angle;
  final double inner;
  final double len;
  final double width;
}

class _SpeedLinesPainter extends CustomPainter {
  _SpeedLinesPainter({required this.center, required this.s});

  final Offset center;
  final double s;

  static final List<_Ray> _rays = () {
    final r = math.Random(11);
    const n = 60;
    return List.generate(
      n,
      (i) => _Ray(
        i / n * math.pi * 2 + (r.nextDouble() - 0.5) * 0.07,
        r.nextDouble(),
        r.nextDouble(),
        r.nextDouble(),
      ),
    );
  }();

  Path _ray(double a, double r0, double r1, double halfAngle) {
    final dir = Offset(math.cos(a), math.sin(a));
    final dirL = Offset(math.cos(a - halfAngle), math.sin(a - halfAngle));
    final dirR = Offset(math.cos(a + halfAngle), math.sin(a + halfAngle));
    return Path()
      ..moveTo(center.dx + dir.dx * r0, center.dy + dir.dy * r0)
      ..lineTo(center.dx + dirL.dx * r1, center.dy + dirL.dy * r1)
      ..lineTo(center.dx + dirR.dx * r1, center.dy + dirR.dy * r1)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final big = size.longestSide;
    final ambient = _seg(s, 0.3, 1.3, Curves.easeOut);
    final burstP = _seg(s, _kImpact, _kImpact + 1.2, Curves.easeOutCubic);
    final burstOn = s >= _kImpact;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (var i = 0; i < _rays.length; i++) {
      final ray = _rays[i];
      final isMint = i % 4 == 0;

      if (ambient > 0.01) {
        final flicker = 0.65 + 0.35 * math.sin(s * 7 + ray.inner * 9);
        final a = 0.05 * ambient * flicker;
        final r0 = big * (0.34 + 0.18 * ray.inner);
        final r1 = r0 + big * (0.18 + 0.3 * ray.len);
        paint.color = (isMint ? _kMint : Colors.white).withValues(alpha: a);
        canvas.drawPath(
            _ray(ray.angle, r0, r1, 0.006 + 0.014 * ray.width), paint);
      }

      if (burstOn && burstP < 0.999) {
        final a = 0.6 * math.pow(1 - burstP, 1.6);
        final r0 = big * (0.10 + 0.22 * ray.inner) + burstP * big * 0.5;
        final r1 = r0 + big * (0.30 + 0.5 * ray.len);
        paint.color = (isMint ? _kMint : Colors.white).withValues(alpha: a);
        canvas.drawPath(
            _ray(ray.angle, r0, r1, 0.01 + 0.03 * ray.width), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) => old.s != s;
}

// ===========================================================================
// SPARKS / PAPER BITS + gentle twinkles around the logo during the hold
// ===========================================================================
class _Spark {
  const _Spark(this.dx, this.speed, this.delay, this.size, this.rot, this.kind);
  final double dx;
  final double speed;
  final double delay;
  final double size;
  final double rot;
  final int kind;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.origin,
    required this.twinkleCenter,
    required this.s,
  });

  final Offset origin;
  final Offset twinkleCenter;
  final double s;

  static final List<_Spark> _ps = () {
    final r = math.Random(5);
    return List.generate(
      28,
      (i) => _Spark(
        r.nextDouble() * 2 - 1,
        0.5 + r.nextDouble() * 0.7,
        r.nextDouble(),
        0.7 + r.nextDouble() * 0.9,
        r.nextDouble() * math.pi * 2,
        i % 3 == 0 ? 1 : 0,
      ),
    );
  }();

  void _star(Canvas canvas, Offset c, double size, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - size)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + size, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + size)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - size, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - size)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    // Eruption: paper scraps + sparkles
    final lt = (s - _kImpact) / 1.25;
    if (lt > 0) {
      for (final p in _ps) {
        final q = ((lt - p.delay * 0.4) / 0.6).clamp(0.0, 1.0);
        if (q <= 0 || q >= 1) continue;
        final ease = q * (2 - q);
        final pos = origin +
            Offset(
              p.dx * 110 * ease + math.sin(q * 6 + p.rot) * 12,
              -p.speed * 280 * ease + 40 * q * q,
            );
        final alpha = (1 - q);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(p.rot + q * 5 * (p.dx.sign == 0 ? 1 : p.dx.sign));
        if (p.kind == 0) {
          paint
            ..style = PaintingStyle.fill
            ..color = _kPaper.withValues(alpha: 0.9 * alpha);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: 6 * p.size, height: 9 * p.size),
              const Radius.circular(1.2),
            ),
            paint,
          );
          paint
            ..color = _kInk.withValues(alpha: 0.6 * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero, width: 3.6 * p.size, height: 4.6 * p.size),
            paint,
          );
          paint.style = PaintingStyle.fill;
        } else {
          paint
            ..style = PaintingStyle.fill
            ..color = _kMint.withValues(alpha: 0.95 * alpha);
          _star(canvas, Offset.zero, 4.5 * p.size, paint);
        }
        canvas.restore();
      }
    }

    // Hero-hold twinkles orbiting the logo
    final tw = _seg(s, _kImpact + 0.6, _kImpact + 1.1);
    if (tw > 0) {
      paint.style = PaintingStyle.fill;
      for (var i = 0; i < 9; i++) {
        final ang = i / 9 * math.pi * 2 + 0.4;
        final rad = 62.0 + 30.0 * ((i * 37) % 10) / 10;
        final phase = i * 1.7;
        final v = math.sin(s * 3.2 + phase);
        final a = math.pow(math.max(0.0, v), 3).toDouble() * tw;
        if (a < 0.02) continue;
        final c = twinkleCenter +
            Offset(math.cos(ang) * rad * 1.15, math.sin(ang) * rad * 0.85);
        paint.color = (i.isEven ? _kMint : Colors.white).withValues(alpha: a);
        _star(canvas, c, 3 + 4 * a, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.s != s;
}

// ===========================================================================
// BRUSH SLASH under the title
// ===========================================================================
class _BrushSlashPainter extends CustomPainter {
  _BrushSlashPainter(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0) return;
    final end = size.width * p;
    final path = Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(
          end * 0.5, size.height * -0.1, end, size.height * 0.34)
      ..quadraticBezierTo(end * 0.5, size.height * 0.55, 0, size.height * 0.62)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = const LinearGradient(colors: [_kCyan, _kMint])
            .createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _BrushSlashPainter old) => old.p != p;
}

// ===========================================================================
// THE BOOK: real 3D-hinged cover + evenly staggered page riffle,
// manga panels on every page
// ===========================================================================
const _kLayouts = <List<List<double>>>[
  // l, t, w, h (fractions of the page's inner area)
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

class _BookPainter extends CustomPainter {
  _BookPainter({
    required this.s,
    required this.center,
    required this.halfW,
    required this.h,
  });

  final double s;
  final Offset center;
  final double halfW;
  final double h;

  // index 0 = cover, 1..3 = manga pages (seconds). Pages are evenly
  // staggered (0.11s apart, equal duration) so the riffle has one rhythm,
  // and the last page lands right before the impact.
  static const _starts = [0.12, 0.55, 0.66, 0.77];
  static const _ends = [0.62, 0.93, 1.04, 1.15];

  @override
  void paint(Canvas canvas, Size size) {
    final op = _seg(s, 0.0, 0.25);
    if (op <= 0) return;
    final appear = _seg(s, 0.0, 0.40, Curves.easeOutBack);
    final openP = _seg(s, 0.12, 0.62, Curves.easeInOutCubic);
    final dx = -halfW / 2 * (1 - openP);
    final bob = math.sin(s * 2.8) * 3;
    final since = s - _kImpact;
    final kick = since > 0 ? math.exp(-since * 9) * 0.05 : 0.0;
    // gentle camera push-in during the build-up, relaxing after the hit
    final push = 0.05 *
        _seg(s, 0.3, _kImpact, Curves.easeIn) *
        (1 - _seg(s, _kImpact, _kImpact + 0.5, Curves.easeOut));

    canvas.save();
    canvas.translate(center.dx + dx, center.dy + bob);
    canvas.scale(0.7 + 0.3 * appear + kick + push);

    final bounds =
        Rect.fromCenter(center: Offset.zero, width: halfW * 6, height: h * 3);
    final layered = op < 1;
    if (layered) {
      canvas.saveLayer(
          bounds, Paint()..color = Colors.white.withValues(alpha: op));
    }

    // Glow behind the open book
    if (openP > 0.01) {
      canvas.drawCircle(
        Offset(0, -h * 0.08),
        halfW * 1.7,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _kMint.withValues(alpha: 0.30 * openP),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(
              center: Offset(0, -h * 0.08), radius: halfW * 1.7)),
      );
    }

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-dx, h / 2 + 18),
        width: halfW * (1 + openP) * 0.95,
        height: 24,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Back board
    final board = RRect.fromRectAndRadius(
      Rect.fromLTRB(-2, -h / 2 - 4, halfW + 4, h / 2 + 4),
      const Radius.circular(8),
    );
    canvas.drawRRect(board, Paint()..color = const Color(0xFF0B1118));
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _kMint.withValues(alpha: 0.45),
    );

    // Page block edge + the page revealed on the right
    final pageRect = Rect.fromLTWH(0, -h / 2 + 5, halfW - 5, h - 10);
    for (var i = 3; i >= 1; i--) {
      canvas.drawRect(
        pageRect.shift(Offset(i * 1.4, 0)),
        Paint()..color = _kPaperShade,
      );
    }
    _paperFace(canvas, pageRect, 1, true, 7);

    // Leaves, ordered for correct overlap
    final a = [
      for (var i = 0; i < 4; i++)
        math.pi *
            _seg(
              s,
              _starts[i],
              _ends[i],
              i == 0 ? Curves.easeInOutCubic : Curves.easeInOutSine,
            ),
    ];
    final rightSide = [
      for (var i = 0; i < 4; i++)
        if (a[i] <= math.pi / 2) i,
    ];
    for (final i in rightSide.reversed) {
      _leaf(canvas, i, a[i]);
    }
    for (var i = 0; i < 4; i++) {
      if (a[i] > math.pi / 2) _leaf(canvas, i, a[i]);
    }

    // Spine crease shadow
    if (openP > 0.02) {
      final crease = Rect.fromLTRB(-16, -h / 2, 16, h / 2);
      canvas.drawRect(
        crease,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.38 * openP),
              Colors.transparent,
            ],
          ).createShader(crease),
      );
    }

    // Light beam rising out of the pages at impact; stays softly alive
    final beam = _seg(s, _kImpact - 0.2, _kImpact + 0.1, Curves.easeOut) *
        (1 - 0.55 * _seg(s, _kImpact + 1.2, _kImpact + 2.0)) *
        (0.92 + 0.08 * math.sin(s * 3.0));
    if (beam > 0.01) {
      final path = Path()
        ..moveTo(-halfW * 0.30, 0)
        ..lineTo(-halfW * 0.95, -h * 1.7)
        ..lineTo(halfW * 0.95, -h * 1.7)
        ..lineTo(halfW * 0.30, 0)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              _kMint.withValues(alpha: 0.38 * beam),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTRB(-halfW, -h * 1.7, halfW, 0)),
      );
    }

    if (layered) canvas.restore();
    canvas.restore();
  }

  void _leaf(Canvas canvas, int i, double a) {
    final isCover = i == 0;
    final rect = isCover
        ? Rect.fromLTWH(0, -h / 2, halfW, h)
        : Rect.fromLTWH(0, -h / 2 + 5, halfW - 5, h - 10);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(isCover ? 8 : 3));

    canvas.save();
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..rotateY(a);
    canvas.transform(m.storage);

    final back = a > math.pi / 2;
    if (back) {
      // draw the reverse side un-mirrored
      canvas.translate(rect.right, 0);
      canvas.scale(-1.0, 1.0);
    }
    canvas.clipRRect(rrect, doAntiAlias: true);

    if (isCover) {
      back ? _coverBack(canvas, rect) : _coverFront(canvas, rect);
    } else {
      _paperFace(canvas, rect, back ? (i * 2 + 1) % 3 : (i * 2) % 3, !back, i);
    }

    final sh = math.sin(a);
    if (sh > 0.01) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.05 * sh),
              Colors.black.withValues(alpha: 0.40 * sh),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  // -------------------------------------------------------------------------
  void _coverFront(Canvas canvas, Rect r) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2A3C), Color(0xFF090D15)],
        ).createShader(r),
    );

    final y1 = r.top + r.height * 0.64;
    final y2 = r.top + r.height * 0.38;
    canvas.drawPath(
      Path()
        ..moveTo(r.left, y1)
        ..lineTo(r.right, y2)
        ..lineTo(r.right, y2 + 16)
        ..lineTo(r.left, y1 + 16)
        ..close(),
      Paint()..color = _kMint.withValues(alpha: 0.92),
    );
    canvas.drawPath(
      Path()
        ..moveTo(r.left, y1 + 24)
        ..lineTo(r.right, y2 + 24)
        ..lineTo(r.right, y2 + 27)
        ..lineTo(r.left, y1 + 27)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );

    canvas.drawRect(
      r.deflate(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _kMint.withValues(alpha: 0.55),
    );

    _text(
      canvas,
      'MANGA',
      Offset(r.left + 22, r.top + 22),
      TextStyle(
        color: Colors.white,
        fontSize: halfW * 0.19,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.5,
      ),
    );
    _text(
      canvas,
      'READER',
      Offset(r.left + 23, r.top + 22 + halfW * 0.24),
      TextStyle(
        color: _kMint,
        fontSize: halfW * 0.095,
        fontWeight: FontWeight.w800,
        letterSpacing: 4,
      ),
    );

    final vol = TextPainter(
      text: TextSpan(
        text: 'VOL. 01',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: halfW * 0.085,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    vol.paint(canvas, Offset(r.right - 22 - vol.width, r.bottom - 28));

    final hinge = Rect.fromLTWH(r.left, r.top, 14, r.height);
    canvas.drawRect(
      hinge,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(hinge),
    );
  }

  void _coverBack(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF0F1722));
    canvas.drawRect(
      r.deflate(10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _kMint.withValues(alpha: 0.25),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: 'MANGA READER',
        style: TextStyle(
          color: _kMint.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    final hinge = Rect.fromLTWH(r.right - 22, r.top, 22, r.height);
    canvas.drawRect(
      hinge,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
        ).createShader(hinge),
    );
  }

  // -------------------------------------------------------------------------
  void _paperFace(
      Canvas canvas, Rect rect, int layoutIdx, bool spineLeft, int seed) {
    canvas.drawRect(rect, Paint()..color = _kPaper);

    final inner = Rect.fromLTRB(
      rect.left + (spineLeft ? 18 : 10),
      rect.top + 12,
      rect.right - (spineLeft ? 10 : 18),
      rect.bottom - 12,
    );

    final layout = _kLayouts[layoutIdx % _kLayouts.length];
    for (var i = 0; i < layout.length; i++) {
      final f = layout[i];
      final pr = Rect.fromLTWH(
        inner.left + f[0] * inner.width,
        inner.top + f[1] * inner.height,
        f[2] * inner.width,
        f[3] * inner.height,
      );
      _panel(canvas, pr, (seed + layoutIdx * 3 + i) % 4);
    }

    const g = 26.0;
    final gr = spineLeft
        ? Rect.fromLTWH(rect.left, rect.top, g, rect.height)
        : Rect.fromLTWH(rect.right - g, rect.top, g, rect.height);
    canvas.drawRect(
      gr,
      Paint()
        ..shader = LinearGradient(
          colors: spineLeft
              ? [Colors.black.withValues(alpha: 0.22), Colors.transparent]
              : [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
        ).createShader(gr),
    );
  }

  void _panel(Canvas canvas, Rect pr, int kind) {
    canvas.save();
    canvas.clipRect(pr);
    canvas.drawRect(pr, Paint()..color = Colors.white);

    switch (kind) {
      case 0: // screentone fill
        canvas.drawRect(pr, Paint()..color = const Color(0xFFCFC7B6));
        final dot = Paint()..color = _kInk.withValues(alpha: 0.25);
        for (double y = pr.top + 3; y < pr.bottom; y += 5) {
          for (double x = pr.left + 3; x < pr.right; x += 5) {
            canvas.drawCircle(Offset(x, y), 0.9, dot);
          }
        }
        break;
      case 1: // hatching
        final hp = Paint()
          ..color = _kInk.withValues(alpha: 0.55)
          ..strokeWidth = 0.8;
        for (double x = pr.left - pr.height; x < pr.right; x += 5) {
          canvas.drawLine(
              Offset(x, pr.bottom), Offset(x + pr.height, pr.top), hp);
        }
        break;
      case 2: // focus lines
        final lp = Paint()
          ..color = _kInk.withValues(alpha: 0.7)
          ..strokeWidth = 1.1;
        final c = pr.center;
        final far = pr.longestSide;
        final min = pr.shortestSide * 0.2;
        for (var k = 0; k < 20; k++) {
          final ang = k / 20 * math.pi * 2;
          final d = Offset(math.cos(ang), math.sin(ang));
          canvas.drawLine(c + d * min, c + d * far, lp);
        }
        break;
      default: // speech bubble
        final bc =
            Offset(pr.center.dx - pr.width * 0.08, pr.top + pr.height * 0.38);
        final br = Rect.fromCenter(
            center: bc, width: pr.width * 0.58, height: pr.height * 0.34);
        final tail = Path()
          ..moveTo(bc.dx - 4, br.bottom - 1)
          ..lineTo(bc.dx - 10, br.bottom + pr.height * 0.14)
          ..lineTo(bc.dx + 6, br.bottom - 1)
          ..close();
        canvas.drawPath(tail, Paint()..color = Colors.white);
        canvas.drawPath(
          tail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = _kInk,
        );
        canvas.drawOval(br, Paint()..color = Colors.white);
        canvas.drawOval(
          br,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = _kInk,
        );
        final tl = Paint()
          ..color = _kInk.withValues(alpha: 0.6)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(br.left + br.width * 0.25, bc.dy - 3),
            Offset(br.right - br.width * 0.25, bc.dy - 3), tl);
        canvas.drawLine(Offset(br.left + br.width * 0.32, bc.dy + 3),
            Offset(br.right - br.width * 0.32, bc.dy + 3), tl);
    }
    canvas.restore();

    canvas.drawRect(
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = _kInk,
    );
  }

  void _text(Canvas canvas, String str, Offset o, TextStyle st) {
    final tp = TextPainter(
      text: TextSpan(text: str, style: st),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _BookPainter old) =>
      old.s != s || old.halfW != halfW || old.h != h || old.center != center;
}
