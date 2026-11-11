import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 64,
    this.borderRadius,
    this.withGlow = true,
  });

  final double size;
  final double? borderRadius;
  final bool withGlow;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.22);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: withGlow
            ? [
                BoxShadow(
                  color: const Color(0xFF00FFA3).withValues(alpha: 0.35),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.08),
                ),
                BoxShadow(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                  blurRadius: size * 0.2,
                  offset: Offset(0, size * 0.04),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/logo/shelfmark_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
