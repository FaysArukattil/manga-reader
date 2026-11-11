import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ReaderAudio {
  ReaderAudio._();
  static final ReaderAudio instance = ReaderAudio._();

  AudioPlayer? _player;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      _player?.setVolume(0.5);
      _initialized = true;
    } catch (_) {}
  }

  Future<void> playPageTurn(
      {bool soundEnabled = true, bool hapticsEnabled = true}) async {
    if (hapticsEnabled) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (!soundEnabled) return;

    try {
      if (_player == null) await init();
      // Stop previous in case user is swiping quickly
      await _player?.stop();
      await _player?.play(
        AssetSource('audio/page_flip.mp3'),
        mode: PlayerMode.lowLatency,
        volume: 0.65,
      );
    } catch (_) {
      // Audio playback should never crash the reader
    }
  }

  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _initialized = false;
  }
}
