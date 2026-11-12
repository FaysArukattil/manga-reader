import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/components/play_store_update_card.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String playStorePackage = 'com.faysarukattil.mangareader';
  static const String _prefLastCheckTime = 'last_play_update_check';
  static const String _prefDismissedVersion = 'dismissed_update_version_code';

  bool _isChecking = false;

  /// Check whether an update is available from Google Play.
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info;
    } catch (e) {
      debugPrint('[UpdateService] check error (expected if dev/sideloaded): $e');
      return null;
    }
  }

  /// Launches Google Play Store page directly for this app.
  Future<bool> openPlayStore() async {
    final marketUri = Uri.parse('market://details?id=$playStorePackage');
    final webUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$playStorePackage');

    try {
      if (await canLaunchUrl(marketUri)) {
        return await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    try {
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Executes update via Google Play In-App Updates, falling back to Play Store app.
  Future<void> performUpdate(BuildContext context, {AppUpdateInfo? info}) async {
    if (kIsWeb || !Platform.isAndroid) {
      await openPlayStore();
      return;
    }

    try {
      // 1. Try immediate update via Play Store API
      if (info?.immediateUpdateAllowed ?? true) {
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) {
          return;
        }
      }
    } catch (e) {
      debugPrint(
          '[UpdateService] performImmediateUpdate failed: $e, falling back to Store');
    }

    // 2. Fallback: Launch Google Play Store directly
    final opened = await openPlayStore();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Play Store automatically.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Displays the Google Play update card.
  void showUpdateCard(
    BuildContext context, {
    AppUpdateInfo? info,
    VoidCallback? onDismiss,
  }) {
    showPlayStoreUpdateCard(context, info: info, onDismiss: onDismiss);
  }

  /// Automatic check on startup or manual check triggered by user.
  /// When [isManual] is false, checks are throttled to once every 12 hours.
  Future<void> checkAndPromptUpdate(
    BuildContext context, {
    bool isManual = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Google Play in-app updates are only available on Android devices.'),
          ),
        );
      }
      return;
    }

    if (_isChecking) return;
    _isChecking = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isManual) {
        final last = prefs.getInt(_prefLastCheckTime) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        // Check at most once every 12 hours on auto-check
        if (now - last < 12 * 60 * 60 * 1000) {
          _isChecking = false;
          return;
        }
        await prefs.setInt(_prefLastCheckTime, now);
      }

      final info = await checkForUpdate();
      _isChecking = false;

      if (!context.mounted) return;

      if (info != null &&
          info.updateAvailability == UpdateAvailability.updateAvailable) {
        // If not manual, check if this version code was already dismissed
        final dismissed = prefs.getInt(_prefDismissedVersion) ?? -1;
        if (!isManual && info.availableVersionCode == dismissed) {
          return;
        }

        // Show the Google Play update card
        showPlayStoreUpdateCard(
          context,
          info: info,
          onDismiss: () {
            if (info.availableVersionCode != null) {
              prefs.setInt(_prefDismissedVersion, info.availableVersionCode!);
            }
          },
        );
      } else if (isManual) {
        // If user manually tapped Check for Updates and app is up to date or dev build
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00C875), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're using the latest version of Manga Reader!",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Open Play Store',
              textColor: const Color(0xFF00FFA3),
              onPressed: () => openPlayStore(),
            ),
            backgroundColor: const Color(0xFF13151A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: const Color(0xFF00C875).withValues(alpha: 0.3),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      _isChecking = false;
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not reach Google Play Update Service.'),
            action: SnackBarAction(
              label: 'View on Store',
              textColor: const Color(0xFF00FFA3),
              onPressed: () => openPlayStore(),
            ),
            backgroundColor: const Color(0xFF13151A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
