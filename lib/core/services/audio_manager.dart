import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  bool _isSpeakerOn = false;

  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> init() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('[AudioManager] Init audio players error: $e');
    }
  }

  Future<void> playRingtone() async {
    try {
      HapticFeedback.vibrate();
      // Try playing asset sound if present, otherwise trigger continuous vibration
      await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (e) {
      debugPrint('[AudioManager] Play ringtone warning: $e');
    }
  }

  Future<void> stopRingtone() async {
    try {
      await _ringtonePlayer.stop();
    } catch (e) {
      debugPrint('[AudioManager] Stop ringtone error: $e');
    }
  }

  Future<void> playRingback() async {
    try {
      await _ringbackPlayer.play(AssetSource('sounds/ringback.mp3'));
    } catch (e) {
      debugPrint('[AudioManager] Play ringback warning: $e');
    }
  }

  Future<void> stopRingback() async {
    try {
      await _ringbackPlayer.stop();
    } catch (e) {
      debugPrint('[AudioManager] Stop ringback error: $e');
    }
  }

  Future<void> stopAll() async {
    await stopRingtone();
    await stopRingback();
  }

  Future<void> setSpeakerphone(bool enabled) async {
    try {
      _isSpeakerOn = enabled;
      await Helper.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('[AudioManager] setSpeakerphone error: $e');
    }
  }

  Future<void> toggleSpeakerphone() async {
    await setSpeakerphone(!_isSpeakerOn);
  }
}
