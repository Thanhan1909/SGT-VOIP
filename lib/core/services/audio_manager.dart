import 'dart:math' as math;
import 'dart:typed_data';

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
  late final Uint8List _ringtoneBytes;
  late final Uint8List _ringbackBytes;

  bool _initialized = false;
  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<void> init() async {
    if (_initialized) return;
    _ringtoneBytes = _buildWav(
      frequencies: const [853, 960],
      toneSeconds: 1.2,
      totalSeconds: 3,
    );
    _ringbackBytes = _buildWav(
      frequencies: const [440, 480],
      toneSeconds: 1.8,
      totalSeconds: 4,
    );
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
    _initialized = true;
    debugPrint(
        '[AudioManager] Initialized ringtone/ringback and audio routing');
  }

  Future<void> playRingtone() async {
    try {
      await init();
      await _ringbackPlayer.stop();
      await HapticFeedback.vibrate();
      await _ringtonePlayer.play(BytesSource(_ringtoneBytes));
    } catch (error) {
      debugPrint('[AudioManager] Ringtone warning: $error');
    }
  }

  Future<void> stopRingtone() => _ringtonePlayer.stop();

  Future<void> playRingback() async {
    try {
      await init();
      await _ringtonePlayer.stop();
      await _ringbackPlayer.play(BytesSource(_ringbackBytes));
    } catch (error) {
      debugPrint('[AudioManager] Ringback warning: $error');
    }
  }

  Future<void> stopRingback() => _ringbackPlayer.stop();

  Future<void> stopAll() async {
    await Future.wait([_ringtonePlayer.stop(), _ringbackPlayer.stop()]);
  }

  Future<void> setSpeakerphone(bool enabled) async {
    try {
      _isSpeakerOn = enabled;
      if (!kIsWeb) {
        await Helper.setSpeakerphoneOn(enabled);
      }
    } catch (error) {
      debugPrint('[AudioManager] setSpeakerphone error: $error');
    }
  }

  Future<void> toggleSpeakerphone() async {
    await setSpeakerphone(!_isSpeakerOn);
  }

  Uint8List _buildWav({
    required List<int> frequencies,
    required double toneSeconds,
    required double totalSeconds,
  }) {
    const sampleRate = 8000;
    final sampleCount = (sampleRate * totalSeconds).round();
    final toneSamples = (sampleRate * toneSeconds).round();
    final pcm = Int16List(sampleCount);
    for (var index = 0; index < toneSamples; index++) {
      final time = index / sampleRate;
      final sample = frequencies
              .map((frequency) => math.sin(2 * math.pi * frequency * time))
              .reduce((left, right) => left + right) /
          frequencies.length;
      pcm[index] = (sample * 5500).round();
    }

    final dataLength = pcm.lengthInBytes;
    final bytes = Uint8List(44 + dataLength);
    final data = ByteData.sublistView(bytes);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      data.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return bytes;
  }
}
