import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import '../../services/update_service.dart';
import 'brand_logo.dart';

/// Shows the Google Play Store update card as a modal bottom sheet.
void showPlayStoreUpdateCard(
  BuildContext context, {
  AppUpdateInfo? info,
  VoidCallback? onDismiss,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => PlayStoreUpdateCard(
      info: info,
      onDismiss: onDismiss,
    ),
  );
}

/// Google Play Store Update Card widget.
/// Can be presented in a bottom sheet, dialog, or embedded directly in the UI.
class PlayStoreUpdateCard extends StatelessWidget {
  const PlayStoreUpdateCard({
    super.key,
    this.info,
    this.onDismiss,
  });

  final AppUpdateInfo? info;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final versionCode = info?.availableVersionCode;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0E11),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF00C875).withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: const Color(0xFF00C875).withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Google Play Store Header Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D24),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GooglePlayTriColorIcon(),
                        const SizedBox(width: 6),
                        const Text(
                          'Google Play',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      onDismiss?.call();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // App Icon & Title
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const BrandLogo(size: 52, withGlow: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Update Available',
                          style: TextStyle(
                            color: Color(0xFF00FFA3),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Shelfmark Manga Reader',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (versionCode != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Build $versionCode • Google Play Release',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // What's New Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF13151A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: Color(0xFF00C875), size: 16),
                        SizedBox(width: 8),
                        Text(
                          "What's in this update",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureBullet(
                      'Fixed vertical webtoon slice layout and overlap issues',
                    ),
                    const SizedBox(height: 6),
                    _buildFeatureBullet(
                      'Full chapter loading for virtualized readers (50–100+ pages)',
                    ),
                    const SizedBox(height: 6),
                    _buildFeatureBullet(
                      'Smooth continuous scrolling and stability optimizations',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        onDismiss?.call();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Not Now',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await UpdateService.instance.performUpdate(
                          context,
                          info: info,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C875),
                        foregroundColor: const Color(0xFF07080A),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.system_update_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Update on Play Store',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF00C875),
            size: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Stylized Google Play tricolor symbol
class _GooglePlayTriColorIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: CustomPaint(
        painter: _PlayIconPainter(),
      ),
    );
  }
}

class _PlayIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Google Play triangle colors
    final paintBlue = Paint()..color = const Color(0xFF00C3FF);
    final paintGreen = Paint()..color = const Color(0xFF00E676);
    final paintRed = Paint()..color = const Color(0xFFFF3366);
    final paintYellow = Paint()..color = const Color(0xFFFFD600);

    // Main triangle outline
    final path = Path()
      ..moveTo(w * 0.1, 0)
      ..lineTo(w * 0.95, h * 0.5)
      ..lineTo(w * 0.1, h)
      ..close();

    // Clip to triangle and paint gradient sectors
    canvas.save();
    canvas.clipPath(path);

    // Blue top sector
    final p1 = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.6, h * 0.5)
      ..lineTo(0, h * 0.5)
      ..close();
    canvas.drawPath(p1, paintBlue);

    // Red bottom sector
    final p2 = Path()
      ..moveTo(0, h * 0.5)
      ..lineTo(w * 0.6, h * 0.5)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p2, paintRed);

    // Green right tip
    final p3 = Path()
      ..moveTo(w * 0.6, h * 0.5)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h * 0.2)
      ..close();
    canvas.drawPath(p3, paintGreen);

    // Yellow right bottom tip
    final p4 = Path()
      ..moveTo(w * 0.6, h * 0.5)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h * 0.8)
      ..close();
    canvas.drawPath(p4, paintYellow);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
