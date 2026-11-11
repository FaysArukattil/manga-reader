import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Highly optimized tactile page-turn audio engine:
/// - Uses pre-decoded, zero-latency 16-bit PCM WAV assets (zero pre-delay).
/// - Dynamic velocity & speed modulation (swiping fast plays faster, slow plays slower).
/// - Micro-peel rustle for small finger movements; crisp paper flip for full turns.
class ReaderAudio {
  ReaderAudio._();
  static final ReaderAudio instance = ReaderAudio._();

  AudioPlayer? _flipPlayer;
  AudioPlayer? _peelPlayer;
  bool _initialized = false;

  static final Source _flipSource = AssetSource('audio/page_flip.wav');
  static final Source _peelSource = AssetSource('audio/page_peel.wav');

  Future<void> init() async {
    if (_initialized) return;
    try {
      _flipPlayer = AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setVolume(0.18);
      _peelPlayer = AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setVolume(0.12);

      await _flipPlayer?.setSource(_flipSource);
      await _peelPlayer?.setSource(_peelSource);
      _initialized = true;
    } catch (_) {}
  }

  /// Plays the crisp, short paper flip sound modulated by the finger speed.
  void playPageTurn({
    double speed = 1.0,
    bool soundEnabled = true,
    bool hapticsEnabled = true,
  }) {
    if (hapticsEnabled) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }

    if (!soundEnabled) return;

    try {
      final rate = speed.clamp(0.75, 1.6);
      if (_flipPlayer == null || !_initialized) {
        init().then((_) {
          _flipPlayer?.setVolume(0.18);
          _flipPlayer?.setPlaybackRate(rate);
          _flipPlayer?.play(_flipSource, mode: PlayerMode.lowLatency);
        });
        return;
      }
      _flipPlayer?.setVolume(0.18);
      _flipPlayer?.setPlaybackRate(rate);
      _flipPlayer?.stop().then((_) {
        _flipPlayer?.play(_flipSource, mode: PlayerMode.lowLatency);
      });
    } catch (_) {}
  }

  /// Plays the subtle paper peel rustle when user begins moving finger.
  void playPagePeel({
    double speed = 1.0,
    bool soundEnabled = true,
    bool hapticsEnabled = true,
  }) {
    if (hapticsEnabled) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (!soundEnabled) return;
    try {
      final rate = speed.clamp(0.7, 1.4);
      if (_peelPlayer == null || !_initialized) {
        init().then((_) {
          _peelPlayer?.setVolume(0.12);
          _peelPlayer?.setPlaybackRate(rate);
          _peelPlayer?.play(_peelSource, mode: PlayerMode.lowLatency);
        });
        return;
      }
      _peelPlayer?.setVolume(0.12);
      _peelPlayer?.setPlaybackRate(rate);
      _peelPlayer?.stop().then((_) {
        _peelPlayer?.play(_peelSource, mode: PlayerMode.lowLatency);
      });
    } catch (_) {}
  }

  /// Immediately stops audio if user cancels the turn or stops moving.
  void stop() {
    try {
      _flipPlayer?.stop();
      _peelPlayer?.stop();
    } catch (_) {}
  }

  void dispose() {
    try {
      _flipPlayer?.dispose();
      _peelPlayer?.dispose();
    } catch (_) {}
    _flipPlayer = null;
    _peelPlayer = null;
    _initialized = false;
  }
}
