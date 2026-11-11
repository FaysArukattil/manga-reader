import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';

// ===========================================================================
// CONFIG
// ===========================================================================

/// Drop a transparent PNG (head + shoulders, ~900px wide) here for a
/// "real" Luffy. The rubber mesh deformation works on ANY image.
/// If the asset is missing, a built-in illustrated Luffy is used instead.
/// Remember to add it under `flutter: assets:` in pubspec.yaml.
const _kLuffyAsset = 'assets/onboarding/luffy.png';

const _kBg = Color(0xFF07080C);
const _kMint = Color(0xFF00FFA3);
const _kPullThreshold = 150.0; // px of stretch needed to start
const _kPullMax = 230.0;

// ===========================================================================
// DATA
// ===========================================================================
class _Show {
  const _Show(this.title, this.genre, this.a, this.b);
  final String title;
  final String genre;
  final Color a;
  final Color b;
}

const _kShows = <_Show>[
  _Show('ONE\nPIECE', 'ADVENTURE', Color(0xFFB91C1C), Color(0xFF450A0A)),
  _Show('JUJUTSU\nKAISEN', 'DARK SHONEN', Color(0xFF7E22CE), Color(0xFF3B0764)),
  _Show('CHAINSAW\nMAN', 'HORROR', Color(0xFFEA580C), Color(0xFF7C2D12)),
  _Show('DANDA\nDAN', 'OCCULT SCI-FI', Color(0xFF0D9488), Color(0xFF134E4A)),
  _Show(
      'SOLO\nLEVELING', 'ACTION FANTASY', Color(0xFF1D4ED8), Color(0xFF0F172A)),
  _Show('NARUTO', 'SHONEN', Color(0xFFF59E0B), Color(0xFF92400E)),
  _Show('DEMON\nSLAYER', 'ACTION', Color(0xFF059669), Color(0xFF064E3B)),
  _Show(
      'ATTACK ON\nTITAN', 'DARK FANTASY', Color(0xFF78716C), Color(0xFF1C1917)),
  _Show('VINLAND\nSAGA', 'HISTORICAL', Color(0xFF0EA5E9), Color(0xFF0C4A6E)),
  _Show('BERSERK', 'DARK FANTASY', Color(0xFF475569), Color(0xFF020617)),
  _Show('BLUE\nLOCK', 'SPORTS', Color(0xFF2563EB), Color(0xFF1E1B4B)),
  _Show('SPY x\nFAMILY', 'COMEDY', Color(0xFFEC4899), Color(0xFF831843)),
];

// ===========================================================================
// SPRING
// ===========================================================================
class _Spring extends ChangeNotifier {
  _Spring({required this.stiffness, required this.damping});

  final double stiffness;
  final double damping;

  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  bool dragging = false;
  double t = 0;

  bool get atRest => !dragging && pos.distance < 0.2 && vel.distance < 2;

  void setPos(Offset p) {
    pos = p;
    notifyListeners();
  }

  void poke() => notifyListeners();

  bool step(double dt) {
    if (dragging) return false;
    if (atRest) {
      if (pos != Offset.zero || vel != Offset.zero) {
        pos = Offset.zero;
        vel = Offset.zero;
        notifyListeners();
      }
      return false;
    }
    const sub = 3;
    final h = dt / sub;
    for (var i = 0; i < sub; i++) {
      final f = (-pos) * stiffness - vel * damping;
      vel += f * h;
      pos += vel * h;
    }
    notifyListeners();
    return true;
  }
}

// ===========================================================================
// PAGE
// ===========================================================================
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _float;
  late final AnimationController _wall;
  late final AnimationController _entry;
  late final Animation<double> _revealLuffy;
  late final Animation<double> _revealA;
  late final Animation<double> _revealB;

  final _spring = _Spring(stiffness: 200, damping: 6);
  Duration _lastTick = Duration.zero;
  double _time = 0;

  ui.Image? _luffyImg;
  Size _area = Size.zero;

  Offset _grab = Offset.zero;
  bool _panActive = false;
  bool _interacted = false;
  bool _launching = false;
  int _level = 0;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _wall = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    )..repeat();

    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
    _revealLuffy = CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.1, 0.6, curve: Curves.easeOutCubic));
    _revealA = CurvedAnimation(
        parent: _entry, curve: const Interval(0.4, 0.8, curve: Curves.easeOut));
    _revealB = CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.55, 1.0, curve: Curves.easeOut));

    _ticker = createTicker(_onTick)..start();
    _loadImage();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _float.dispose();
    _wall.dispose();
    _entry.dispose();
    _spring.dispose();
    _luffyImg?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.033);
    _lastTick = elapsed;
    _time += dt;
    _spring.t = _time;
    final moved = _spring.step(dt);
    if (!moved) _spring.poke(); // keeps the idle breathing animation alive
  }

  Future<void> _loadImage() async {
    ui.Image img;
    try {
      final data = await rootBundle.load(_kLuffyAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 900,
      );
      img = (await codec.getNextFrame()).image;
    } catch (_) {
      img = await _paintFallbackLuffy();
    }
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() => _luffyImg = img);
  }

  // -------------------------------------------------------------------------
  // Pull-to-start gesture
  // -------------------------------------------------------------------------
  double get _progress =>
      (_spring.pos.distance / _kPullThreshold).clamp(0.0, 1.0);

  void _onPanStart(DragStartDetails d) {
    final img = _luffyImg;
    if (_launching || img == null) return;
    final rect = _RubberLuffyPainter.imageRect(_area, img);
    _panActive = rect.inflate(24).contains(d.localPosition);
    if (!_panActive) return;
    _grab = d.localPosition;
    _spring.dragging = true;
    _spring.vel = Offset.zero;
    _level = 0;
    HapticFeedback.selectionClick();
    if (!_interacted) setState(() => _interacted = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_panActive) return;
    final len = _spring.pos.distance;
    // Rubber resistance: harder to pull the further it stretches
    final k = (0.95 - 0.5 * (len / _kPullMax)).clamp(0.3, 0.95);
    var p = _spring.pos + d.delta * k;
    if (p.distance > _kPullMax) p = p / p.distance * _kPullMax;
    _spring.setPos(p);

    final lvl = (_progress * 3).floor().clamp(0, 3);
    if (lvl > _level) {
      if (lvl >= 3) {
        HapticFeedback.heavyImpact();
      } else if (lvl == 2) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    } else if (lvl < _level) {
      HapticFeedback.selectionClick();
    }
    _level = lvl;
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_panActive) return;
    _panActive = false;
    _spring.dragging = false;
    _spring.vel = Offset.zero;
    if (_progress >= 1) {
      _launch();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _launch() {
    if (_launching) return;
    setState(() => _launching = true);
    HapticFeedback.heavyImpact();
    // Let the rubber snap back with its overshoot, then go.
    Future<void>.delayed(const Duration(milliseconds: 520), _onGetStarted);
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

  Widget _reveal(Animation<double> a, Widget child) {
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
            .animate(a),
        child: child,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Scrolling wall of every show that lives in the app
          Opacity(opacity: 0.75, child: _PosterWall(t: _wall)),

          // 2. Warm glow behind Luffy
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.15),
                    radius: 0.85,
                    colors: [
                      Color(0x55FACC15),
                      Color(0x22EF4444),
                      Color(0x00000000)
                    ],
                    stops: [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),

          // 3. Readability gradient
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _kBg.withValues(alpha: 0.80),
                      _kBg.withValues(alpha: 0.10),
                      _kBg.withValues(alpha: 0.45),
                      _kBg,
                    ],
                    stops: const [0.0, 0.28, 0.6, 0.82],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_stories_rounded,
                                size: 14, color: _kMint),
                            SizedBox(width: 6),
                            Text(
                              'ALL YOUR MANGA. ONE APP.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _launching ? null : _onGetStarted,
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Luffy
                Expanded(child: _buildLuffyArea()),

                // Copy + pull-to-start
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _reveal(
                        _revealA,
                        const Text(
                          'Every series you love.\nOne app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _reveal(
                        _revealA,
                        const Text(
                          'One Piece, Jujutsu Kaisen, Chainsaw Man and thousands more. Track, bookmark and read with zero ads.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _reveal(_revealB, _buildMeter()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLuffyArea() {
    return LayoutBuilder(
      builder: (context, c) {
        _area = Size(c.maxWidth, c.maxHeight);
        final img = _luffyImg;
        return FadeTransition(
          opacity: _revealLuffy,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(_revealLuffy),
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: () {
                _panActive = false;
                _spring.dragging = false;
              },
              child: SizedBox.expand(
                child: img == null
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _RubberLuffyPainter(
                          image: img,
                          spring: _spring,
                          pulse: _float,
                          grab: () => _grab,
                          showHint: () => !_interacted && !_launching,
                          progress: () => _launching ? 1.0 : _progress,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMeter() {
    return AnimatedBuilder(
      animation: _spring,
      builder: (context, _) {
        final p = _launching ? 1.0 : _progress;
        final label = p >= 1
            ? 'RELEASE TO START!'
            : p > 0.05
                ? 'KEEP STRETCHING...'
                : "PULL LUFFY TO GET STARTED";
        final active = p > 0.05;
        return Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xFF0E1620),
            border: Border.all(
              color: _kMint.withValues(alpha: active ? 0.7 : 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _kMint.withValues(alpha: 0.10 + p * 0.25),
                blurRadius: 18 + p * 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: p,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _kMint.withValues(alpha: 0.10),
                            _kMint.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: p >= 1 ? Colors.black : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_double_arrow_down_rounded,
                        size: 18,
                        color: p >= 1 ? Colors.black : _kMint,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// POSTER WALL (every show in the app, endlessly scrolling in 3 columns)
// ===========================================================================
class _PosterWall extends StatelessWidget {
  const _PosterWall({required this.t});

  final Animation<double> t;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final colW = w * 0.36;
        final posterH = colW * 1.45;
        const gap = 12.0;
        final itemH = posterH + gap;
        const perLoop = 6;
        final loopH = perLoop * itemH;

        Widget column(int index) {
          final items = [
            for (var i = 0; i < perLoop; i++)
              _kShows[(index * 4 + i) % _kShows.length],
          ];
          final doubled = [...items, ...items];
          final up = index.isOdd;
          final phase = index * 0.33;
          return SizedBox(
            width: colW,
            height: h * 1.5,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: AnimatedBuilder(
                  animation: t,
                  child: RepaintBoundary(
                    child: Column(
                      children: [
                        for (final s in doubled)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child:
                                _Poster(show: s, width: colW, height: posterH),
                          ),
                      ],
                    ),
                  ),
                  builder: (context, child) {
                    final v = (t.value + phase) % 1.0;
                    final dy = up ? -v * loopH : -loopH + v * loopH;
                    return Transform.translate(
                        offset: Offset(0, dy), child: child);
                  },
                ),
              ),
            ),
          );
        }

        return ClipRect(
          child: OverflowBox(
            maxWidth: w * 1.5,
            maxHeight: h * 1.5,
            child: Transform.rotate(
              angle: -0.16,
              child: SizedBox(
                width: w * 1.5,
                height: h * 1.5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    column(0),
                    const SizedBox(width: gap),
                    column(1),
                    const SizedBox(width: gap),
                    column(2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster(
      {required this.show, required this.width, required this.height});

  final _Show show;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [show.a, show.b],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _HalftonePainter()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    show.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: width * 0.14,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    show.genre,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: width * 0.055,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
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

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.10);
    const gap = 11.0;
    for (double y = 0; y < size.height + gap; y += gap) {
      final shift = (y / gap).floor().isOdd ? gap / 2 : 0.0;
      for (double x = 0; x < size.width + gap; x += gap) {
        final t = ((x / size.width) + (1 - y / size.height)) / 2;
        canvas.drawCircle(Offset(x + shift, y), 0.5 + 2.3 * t * t, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// RUBBER LUFFY: mesh-warped image (Gomu Gomu face / body stretch)
// ===========================================================================
class _RubberLuffyPainter extends CustomPainter {
  _RubberLuffyPainter({
    required this.image,
    required this.spring,
    required this.pulse,
    required this.grab,
    required this.showHint,
    required this.progress,
  }) : super(repaint: Listenable.merge([spring, pulse]));

  final ui.Image image;
  final _Spring spring;
  final Animation<double> pulse;
  final Offset Function() grab;
  final bool Function() showHint;
  final double Function() progress;

  static const _cols = 16;
  static const _rows = 20;

  static final Uint16List _indices = () {
    final l = Uint16List(_cols * _rows * 6);
    var k = 0;
    for (var j = 0; j < _rows; j++) {
      for (var i = 0; i < _cols; i++) {
        final a = j * (_cols + 1) + i;
        final b = a + 1;
        final c = a + _cols + 1;
        final d = c + 1;
        l[k++] = a;
        l[k++] = b;
        l[k++] = c;
        l[k++] = b;
        l[k++] = d;
        l[k++] = c;
      }
    }
    return l;
  }();

  /// Image is fitted to the bottom-center of the available area.
  /// Tall full-body art: show head -> shorts and fade the legs out, so
  /// Luffy is big on screen. Square-ish busts are shown whole.
  static double cropOf(ui.Image img) =>
      img.height / img.width > 1.3 ? 0.72 : 1.0;

  static Rect imageRect(Size size, ui.Image img) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble() * cropOf(img);
    final s = math.min(size.width * 0.98 / iw, size.height / ih);
    final w = iw * s;
    final h = ih * s;
    return Rect.fromLTWH((size.width - w) / 2, size.height - h, w, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = imageRect(size, image);
    final crop = cropOf(image);
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();

    final p = spring.pos;
    final pd = p.distance;
    final pdir = pd > 0.5 ? p / pd : Offset.zero;
    final pn = Offset(-pdir.dy, pdir.dx);
    final g = grab();
    final r = rect.shortestSide * (crop < 1 ? 0.32 : 0.42);
    final r2 = r * r;

    final speed = spring.dragging ? 0.0 : spring.vel.distance;
    final amp = (speed * 0.02).clamp(0.0, 14.0);
    final vdir = speed > 1 ? spring.vel / speed : Offset.zero;
    final vn = Offset(-vdir.dy, vdir.dx);
    final breath = math.sin(spring.t * 2.0) * 3.0;

    const n = (_cols + 1) * (_rows + 1);
    final pos = Float32List(n * 2);
    final tex = Float32List(n * 2);

    var k = 0;
    for (var j = 0; j <= _rows; j++) {
      final v = j / _rows;
      for (var i = 0; i <= _cols; i++) {
        final u = i / _cols;
        final bx = rect.left + u * rect.width;
        final by = rect.top + v * rect.height;

        final rx = bx - g.dx;
        final ry = by - g.dy;
        final d2 = rx * rx + ry * ry;
        final f = math.exp(-d2 / r2);

        // Pin the bottom of the image so the body stays put
        final pin = 1 - 0.75 * v * v * v;

        var ox = (p.dx * f + p.dx * 0.10 * (1 - v)) * pin;
        var oy = (p.dy * f + p.dy * 0.10 * (1 - v)) * pin;

        // Rubber necking: the stretched part gets thinner
        if (pd > 1) {
          final perp = rx * pn.dx + ry * pn.dy;
          final squeeze = -perp * 0.35 * f * (pd / (pd + 120));
          ox += pn.dx * squeeze;
          oy += pn.dy * squeeze;
        }

        // Jelly ripple after release
        if (amp > 0.5) {
          final w = math.sin(math.sqrt(d2) * 0.045 - spring.t * 26) * amp * f;
          ox += vn.dx * w;
          oy += vn.dy * w;
        }

        oy += breath * (1 - v);

        pos[k] = bx + ox;
        pos[k + 1] = by + oy;
        tex[k] = u * iw;
        tex[k + 1] = v * ih * crop;
        k += 2;
      }
    }

    final shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    );
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: tex,
      indices: _indices,
    );
    final layer =
        Rect.fromLTWH(-100, -100, size.width + 200, size.height + 200);
    if (crop < 1) canvas.saveLayer(layer, Paint());
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..shader = shader
        ..isAntiAlias = true,
    );
    if (crop < 1) {
      // Fade the cropped legs into the background
      canvas.drawRect(
        layer,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(0, rect.bottom - rect.height * 0.24),
            Offset(0, rect.bottom),
            const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ),
      );
      canvas.restore();
    }

    // Idle hint: pulsing ring on the cheek, nudging toward a pull direction
    if (showHint() && spring.atRest) {
      // Full-body art: invite the user to grab the outstretched hand
      final base = crop < 1
          ? rect.topLeft + Offset(rect.width * 0.29, rect.height * 0.30)
          : rect.topLeft + Offset(rect.width * 0.76, rect.height * 0.60);
      final pv = pulse.value;
      final c = base +
          (crop < 1 ? Offset(-pv * 16, pv * 10) : Offset(pv * 18, pv * 10));
      canvas.drawCircle(
        c,
        16 + pv * 6,
        Paint()
          ..color = _kMint.withValues(alpha: 0.35 + (1 - pv) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(c, 4, Paint()..color = _kMint.withValues(alpha: 0.9));
    }

    // Finger progress ring while stretching
    final prog = progress();
    if (spring.dragging || prog > 0.02) {
      final c = g + p;
      canvas.drawCircle(
        c,
        28,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 28),
        -math.pi / 2,
        math.pi * 2 * prog,
        false,
        Paint()
          ..color = _kMint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      if (prog >= 1) {
        canvas.drawCircle(
          c,
          34,
          Paint()
            ..color = _kMint.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RubberLuffyPainter oldDelegate) =>
      oldDelegate.image != image;
}

// ===========================================================================
// BUILT-IN LUFFY ILLUSTRATION (rendered once into a texture, 1.5x for sharpness)
// If assets/onboarding/luffy.png exists it is used instead.
// ===========================================================================
Future<ui.Image> _paintFallbackLuffy() async {
  const sc = 1.5;
  const w = 640.0;
  const h = 760.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(sc);

  const ink = Color(0xFF2B1208);
  const skin = Color(0xFFFFD6B0);
  const skinShade = Color(0xFFE9A97C);
  const hairC = Color(0xFF16131A);
  const strawDark = Color(0xFF7A4B00);

  Paint fillP(Color col) => Paint()
    ..color = col
    ..isAntiAlias = true;
  Paint stroke(double sw, [Color col = ink]) => Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  // ------------------------------------------------------------------ torso
  final torso = Path()
    ..moveTo(30, 760)
    ..quadraticBezierTo(40, 632, 200, 600)
    ..lineTo(440, 600)
    ..quadraticBezierTo(600, 632, 610, 760)
    ..close();
  c.drawPath(
    torso,
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 600),
        const Offset(0, 760),
        const [skin, skinShade],
      ),
  );
  c.drawPath(torso, stroke(6));

  // ------------------------------------------------------------------- neck
  final neck = RRect.fromRectAndRadius(
      const Rect.fromLTWH(262, 520, 116, 120), const Radius.circular(36));
  c.drawRRect(neck, fillP(skinShade));
  c.drawLine(const Offset(263, 545), const Offset(268, 612), stroke(6));
  c.drawLine(const Offset(377, 545), const Offset(372, 612), stroke(6));

  // --------------------------------------------------- chest X scar + vest
  final scar = stroke(9, const Color(0xFF9B3B2A));
  c.drawLine(const Offset(292, 650), const Offset(348, 722), scar);
  c.drawLine(const Offset(348, 650), const Offset(292, 722), scar);

  final vestL = Path()
    ..moveTo(150, 612)
    ..quadraticBezierTo(205, 598, 250, 604)
    ..lineTo(284, 760)
    ..lineTo(118, 760)
    ..quadraticBezierTo(104, 690, 150, 612)
    ..close();
  final vestR = Path()
    ..moveTo(490, 612)
    ..quadraticBezierTo(435, 598, 390, 604)
    ..lineTo(356, 760)
    ..lineTo(522, 760)
    ..quadraticBezierTo(536, 690, 490, 612)
    ..close();
  final vestPaint = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 600),
      const Offset(0, 760),
      const [Color(0xFFE53946), Color(0xFFA51B27)],
    );
  for (final v in [vestL, vestR]) {
    c.drawPath(v, vestPaint);
    c.drawPath(v, stroke(6, const Color(0xFF5A0E15)));
  }

  // ------------------------------------------------------------------- ears
  for (final x in const [141.0, 499.0]) {
    c.drawCircle(Offset(x, 388), 36, fillP(skin));
    c.drawCircle(Offset(x, 388), 36, stroke(6));
    c.drawCircle(Offset(x, 390), 17, fillP(skinShade.withValues(alpha: 0.55)));
  }

  // -------------------------------------------------------------- back hair
  final hair = fillP(hairC);
  c.drawOval(
      Rect.fromCenter(center: const Offset(320, 300), width: 412, height: 350),
      hair);
  c.drawPath(
      Path()
        ..moveTo(130, 330)
        ..lineTo(100, 410)
        ..lineTo(160, 385)
        ..close(),
      hair);
  c.drawPath(
      Path()
        ..moveTo(510, 330)
        ..lineTo(540, 410)
        ..lineTo(480, 385)
        ..close(),
      hair);

  // ------------------------------------------------------------------- face
  final faceRect =
      Rect.fromCenter(center: const Offset(320, 368), width: 366, height: 410);
  final facePath = Path()..addOval(faceRect);
  c.drawPath(
    facePath,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(270, 300),
        300,
        const [Color(0xFFFFE9D2), Color(0xFFFFD6B0), Color(0xFFF0B085)],
        const [0.0, 0.6, 1.0],
      ),
  );
  // cel-shade crescent on the lower right
  c.save();
  c.clipPath(facePath);
  c.drawPath(
    Path.combine(
      PathOperation.difference,
      facePath,
      Path()..addOval(faceRect.shift(const Offset(-24, -18))),
    ),
    fillP(skinShade.withValues(alpha: 0.45)),
  );
  c.restore();

  // blush
  final blush = Paint()
    ..color = const Color(0xFFFF7A7A).withValues(alpha: 0.32)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
  c.drawOval(
      Rect.fromCenter(center: const Offset(205, 440), width: 78, height: 44),
      blush);
  c.drawOval(
      Rect.fromCenter(center: const Offset(435, 440), width: 78, height: 44),
      blush);

  // eyes: big black ovals with anime highlights
  for (final x in const [245.0, 395.0]) {
    c.drawOval(Rect.fromCenter(center: Offset(x, 368), width: 42, height: 54),
        fillP(const Color(0xFF14110F)));
    c.drawCircle(Offset(x - 7, 354), 10, fillP(Colors.white));
    c.drawCircle(Offset(x + 7, 380), 4.5, fillP(Colors.white70));
    c.drawArc(
      Rect.fromCenter(center: Offset(x, 366), width: 50, height: 60),
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      stroke(5, const Color(0xFF14110F)),
    );
  }

  // scar under his left eye (viewer's right)
  final scarEye = stroke(7, const Color(0xFF8F2D2D));
  c.drawPath(
    Path()
      ..moveTo(362, 412)
      ..quadraticBezierTo(395, 425, 428, 414),
    scarEye,
  );
  c.drawLine(const Offset(381, 406), const Offset(379, 428),
      stroke(5, const Color(0xFF8F2D2D)));
  c.drawLine(const Offset(404, 410), const Offset(402, 432),
      stroke(5, const Color(0xFF8F2D2D)));

  // small round nose
  c.drawOval(
      Rect.fromCenter(center: const Offset(320, 407), width: 26, height: 18),
      fillP(skinShade.withValues(alpha: 0.75)));
  c.drawArc(
      Rect.fromCenter(center: const Offset(320, 408), width: 26, height: 18),
      0.2,
      math.pi * 0.7,
      false,
      stroke(4));

  // ----------------------------------------------------------- the big grin
  final mouth = Path()
    ..moveTo(188, 428)
    ..quadraticBezierTo(320, 462, 452, 428)
    ..quadraticBezierTo(446, 540, 320, 548)
    ..quadraticBezierTo(194, 540, 188, 428)
    ..close();
  final teeth = Path()
    ..moveTo(170, 416)
    ..lineTo(470, 416)
    ..lineTo(470, 460)
    ..quadraticBezierTo(320, 494, 170, 460)
    ..close();
  c.save();
  c.clipPath(mouth);
  c.drawPath(mouth, fillP(const Color(0xFF5E1010)));
  c.drawOval(
      Rect.fromCenter(center: const Offset(320, 524), width: 170, height: 80),
      fillP(const Color(0xFFE8607A)));
  c.drawOval(
      Rect.fromCenter(center: const Offset(305, 514), width: 70, height: 26),
      fillP(Colors.white.withValues(alpha: 0.22)));
  c.drawPath(teeth, fillP(const Color(0xFFFFFCF4)));
  c.save();
  c.clipPath(teeth);
  final tl = stroke(2.5, const Color(0xFF8A6A5A));
  for (var x = 214.0; x <= 430; x += 27) {
    c.drawLine(Offset(x, 420), Offset(x, 500), tl);
  }
  c.restore();
  c.drawPath(
    Path()
      ..moveTo(170, 460)
      ..quadraticBezierTo(320, 494, 470, 460),
    stroke(3.5, const Color(0xFF8A6A5A)),
  );
  c.restore();
  c.drawPath(mouth, stroke(7));
  // cheek creases at the corners of the grin
  c.drawPath(
    Path()
      ..moveTo(176, 406)
      ..quadraticBezierTo(158, 428, 176, 452),
    stroke(5),
  );
  c.drawPath(
    Path()
      ..moveTo(464, 406)
      ..quadraticBezierTo(482, 428, 464, 452),
    stroke(5),
  );

  // face outline
  c.drawPath(facePath, stroke(7));

  // ---------------------------------------------------------- messy fringe
  final bangs = Path()
    ..moveTo(165, 190)
    ..lineTo(165, 286)
    ..lineTo(195, 262)
    ..lineTo(215, 304)
    ..lineTo(245, 268)
    ..lineTo(268, 310)
    ..lineTo(300, 272)
    ..lineTo(325, 304)
    ..lineTo(352, 268)
    ..lineTo(380, 312)
    ..lineTo(405, 266)
    ..lineTo(430, 302)
    ..lineTo(455, 262)
    ..lineTo(475, 286)
    ..lineTo(475, 190)
    ..close();
  c.drawPath(bangs, hair);
  c.drawPath(bangs, stroke(3, hairC));
  final sheen = stroke(3, const Color(0xFF3A3A52));
  c.drawLine(const Offset(230, 240), const Offset(218, 282), sheen);
  c.drawLine(const Offset(300, 242), const Offset(300, 270), sheen);
  c.drawLine(const Offset(390, 240), const Offset(402, 280), sheen);

  // eyebrows
  final brow = stroke(12, hairC);
  c.drawPath(
    Path()
      ..moveTo(208, 332)
      ..quadraticBezierTo(244, 312, 282, 324),
    brow,
  );
  c.drawPath(
    Path()
      ..moveTo(358, 324)
      ..quadraticBezierTo(396, 312, 432, 332),
    brow,
  );

  // --------------------------------------------------------------- straw hat
  c.save();
  c.translate(320, 190);
  c.rotate(-0.04);
  c.translate(-320, -190);

  final strawShader = ui.Gradient.linear(
    const Offset(0, 30),
    const Offset(0, 260),
    const [Color(0xFFFFE680), Color(0xFFF2B100)],
  );
  final brim =
      Rect.fromCenter(center: const Offset(320, 184), width: 630, height: 84);
  c.drawOval(brim, Paint()..shader = strawShader);
  c.drawOval(brim, stroke(7, strawDark));
  for (final f in const [0.86, 0.68]) {
    c.drawOval(
      Rect.fromCenter(
          center: const Offset(320, 186), width: 630 * f, height: 84 * f),
      stroke(2.5, strawDark.withValues(alpha: 0.35)),
    );
  }

  final crown = Path()
    ..moveTo(208, 186)
    ..quadraticBezierTo(192, 34, 320, 30)
    ..quadraticBezierTo(448, 34, 432, 186)
    ..quadraticBezierTo(320, 226, 208, 186)
    ..close();
  c.drawPath(crown, Paint()..shader = strawShader);
  c.save();
  c.clipPath(crown);
  // woven lines
  final weave = stroke(2, strawDark.withValues(alpha: 0.28));
  for (var i = -4; i <= 4; i++) {
    c.drawLine(Offset(320 + i * 20.0, 34), Offset(320 + i * 34.0, 230), weave);
  }
  // red band
  c.drawPath(
    Path()
      ..moveTo(180, 128)
      ..quadraticBezierTo(320, 168, 460, 128)
      ..lineTo(460, 260)
      ..lineTo(180, 260)
      ..close(),
    fillP(const Color(0xFFD62828)),
  );
  c.drawPath(
    Path()
      ..moveTo(180, 128)
      ..quadraticBezierTo(320, 168, 460, 128),
    stroke(3, const Color(0xFF8E1313)),
  );
  // highlight
  c.drawOval(
    Rect.fromCenter(center: const Offset(268, 84), width: 90, height: 40),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );
  c.restore();
  c.drawPath(crown, stroke(7, strawDark));
  c.restore();

  final picture = rec.endRecording();
  return picture.toImage((w * sc).toInt(), (h * sc).toInt());
}
