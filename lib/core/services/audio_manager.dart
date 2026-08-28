import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> init() async {
    debugPrint('[AudioManager] Initialized audio manager safely');
  }

  Future<void> playRingtone() async {
    try {
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('[AudioManager] Haptic feedback warning: $e');
    }
  }

  Future<void> stopRingtone() async {}

  Future<void> playRingback() async {}

  Future<void> stopRingback() async {}

  Future<void> stopAll() async {}

  Future<void> setSpeakerphone(bool enabled) async {
    try {
      _isSpeakerOn = enabled;
      if (!kIsWeb) {
        await Helper.setSpeakerphoneOn(enabled);
      }
    } catch (e) {
      debugPrint('[AudioManager] setSpeakerphone error: $e');
    }
  }

  Future<void> toggleSpeakerphone() async {
    await setSpeakerphone(!_isSpeakerOn);
  }
}
