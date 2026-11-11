import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Compact, reusable animated book loader with flipping pages.
/// Can be dropped into any widget tree as an alternative to CircularProgressIndicator.
class MiniBookLoader extends StatefulWidget {
  const MiniBookLoader({
    super.key,
    this.size = 36.0,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  State<MiniBookLoader> createState() => _MiniBookLoaderState();
}

class _MiniBookLoaderState extends State<MiniBookLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeAccent = widget.color ?? const Color(0xFF00FFA3);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _MiniBookPainter(
              progress: _controller.value,
              accentColor: themeAccent,
            ),
          );
        },
      ),
    );
  }
}

class _MiniBookPainter extends CustomPainter {
  _MiniBookPainter({
    required this.progress,
    required this.accentColor,
  });

  final double progress;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final bookW = w * 0.72;
    final bookH = h * 0.58;
    final halfW = bookW / 2;

    // Subtle floating bob
    final bob = math.sin(progress * math.pi * 2) * (h * 0.04);
    canvas.save();
    canvas.translate(cx, cy + bob);

    // Spine & book background (base pages)
    final coverPaint = Paint()
      ..color = const Color(0xFF141923)
      ..style = PaintingStyle.fill;

    // Book back cover
    final coverRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-halfW - 1.5, -bookH / 2 - 1.5, bookW + 3, bookH + 3),
      const Radius.circular(4),
    );
    canvas.drawRRect(coverRect, coverPaint);

    final pageBasePaint = Paint()
      ..color = const Color(0xFFE2DCce)
      ..style = PaintingStyle.fill;

    final spinePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Left base page
    final leftRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(-halfW, -bookH / 2, halfW, bookH),
      topLeft: const Radius.circular(3),
      bottomLeft: const Radius.circular(3),
    );
    canvas.drawRRect(leftRect, pageBasePaint);

    // Right base page
    final rightRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, -bookH / 2, halfW, bookH),
      topRight: const Radius.circular(3),
      bottomRight: const Radius.circular(3),
    );
    canvas.drawRRect(rightRect, pageBasePaint);

    // Multiple flipping leaves
    for (int i = 0; i < 3; i++) {
      final leafPhase = (progress + i * 0.33) % 1.0;
      final angle = math.pi * (1.0 - leafPhase); // flips from right (pi) to left (0)

      if (leafPhase > 0.05 && leafPhase < 0.95) {
        canvas.save();
        // Skew matrix for 3D flip effect around spine (x = 0)
        final cosVal = math.cos(angle);
        final sinVal = math.sin(angle);

        final leafWidth = halfW * cosVal;
        final leafH = bookH * (0.92 + 0.08 * sinVal);

        final leafColor = Color.lerp(
          const Color(0xFFF9F6EE),
          const Color(0xFFCAC2B2),
          sinVal * 0.5,
        )!;

        final leafPaint = Paint()..color = leafColor;
        final leafRect = Rect.fromLTWH(
          leafWidth < 0 ? leafWidth : 0,
          -leafH / 2,
          leafWidth.abs(),
          leafH,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(leafRect, const Radius.circular(2)),
          leafPaint,
        );

        // Subtle text line marks on leaf
        if (leafWidth.abs() > 6) {
          final linePaint = Paint()
            ..color = const Color(0xFF555048).withValues(alpha: 0.4)
            ..strokeWidth = 1.0;

          final lineStartX = leafWidth < 0 ? leafWidth + 2 : 2.0;
          final lineEndX = leafWidth < 0 ? -2.0 : leafWidth - 2;

          canvas.drawLine(
            Offset(lineStartX, -leafH * 0.18),
            Offset(lineEndX, -leafH * 0.18),
            linePaint,
          );
          canvas.drawLine(
            Offset(lineStartX, leafH * 0.18),
            Offset(lineEndX, leafH * 0.18),
            linePaint,
          );
        }

        canvas.restore();
      }
    }

    // Book center spine line
    canvas.drawLine(
      Offset(0, -bookH / 2 - 1),
      Offset(0, bookH / 2 + 1),
      spinePaint,
    );

    // Outer glow pulse
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset.zero, bookW * 0.45, glowPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniBookPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
  }
}
