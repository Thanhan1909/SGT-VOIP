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
  RTCVideoRenderer? _remoteAudioRenderer;
  bool _remoteAudioRendererInitialized = false;
  Uint8List? _ringtoneBytes;
  Uint8List? _ringbackBytes;

  bool _initialized = false;
  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  String? _activeCallId;
  bool _audioRouteInitializedForCall = false;

  /// Resets audio route to earpiece when preparing for a new call (incoming or outgoing).
  Future<void> prepareForCall(String? callId) async {
    _activeCallId = callId;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[AudioManager] prepareForCall error: $e');
      }
    }
  }

  /// Ensures default audio route (earpiece) is applied exactly once per call upon ACCEPTED / CONFIRMED.
  /// If the user has already explicitly pressed the Speakerphone button, their choice is respected.
  Future<void> ensureDefaultAudioRoute(String? callId) async {
    if (callId != null &&
        _activeCallId == callId &&
        _audioRouteInitializedForCall) {
      // Already configured once for this call. Do not override user's manual toggle.
      return;
    }
    _activeCallId = callId;
    _audioRouteInitializedForCall = true;
    if (!_isSpeakerOn && !kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[AudioManager] ensureDefaultAudioRoute error: $e');
      }
    }
  }

  /// Resets audio routing and stops ringtones when call ends or fails.
  Future<void> resetOnCallEnded([String? callId]) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      return;
    }
    _activeCallId = null;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
    await stopAll();
    await detachRemoteStream();
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[AudioManager] resetOnCallEnded error: $e');
      }
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _ringtoneBytes ??= _buildWav(
      frequencies: const [853, 960],
      toneSeconds: 1.2,
      totalSeconds: 3,
    );
    _ringbackBytes ??= _buildWav(
      frequencies: const [440, 480],
      toneSeconds: 1.8,
      totalSeconds: 4,
    );
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
    _initialized = true;
    debugPrint(
      '[AudioManager] Initialized ringtone/ringback and audio routing',
    );
  }

  Future<void> playRingtone() async {
    try {
      await init();
      await _ringbackPlayer.stop();
      await HapticFeedback.vibrate();
      final bytes = _ringtoneBytes;
      if (bytes != null) {
        await _ringtonePlayer.play(BytesSource(bytes));
      }
    } catch (error) {
      debugPrint('[AudioManager] Ringtone warning: $error');
    }
  }

  Future<void> stopRingtone() => _ringtonePlayer.stop();

  Future<void> playRingback() async {
    try {
      await init();
      await _ringtonePlayer.stop();
      final bytes = _ringbackBytes;
      if (bytes != null) {
        await _ringbackPlayer.play(BytesSource(bytes));
      }
    } catch (error) {
      debugPrint('[AudioManager] Ringback warning: $error');
    }
  }

  Future<void> stopRingback() => _ringbackPlayer.stop();

  Future<void> stopAll() async {
    await Future.wait([_ringtonePlayer.stop(), _ringbackPlayer.stop()]);
  }

  /// Attaches the remote WebRTC stream to a renderer.
  ///
  /// On Flutter web, assigning [RTCVideoRenderer.srcObject] creates the hidden
  /// HTML audio element that actually consumes and plays remote audio. Merely
  /// receiving an enabled audio track is not enough to produce sound.
  Future<void> attachRemoteStream(MediaStream stream) async {
    try {
      final renderer = _remoteAudioRenderer ??= RTCVideoRenderer();
      if (!_remoteAudioRendererInitialized) {
        await renderer.initialize();
        _remoteAudioRendererInitialized = true;
      }
      renderer.srcObject = stream;
      debugPrint(
        '[AudioManager] Remote WebRTC stream attached '
        '(${stream.getAudioTracks().length} audio track(s))',
      );
    } catch (error, stack) {
      debugPrint(
        '[AudioManager] Failed to attach remote WebRTC stream: '
        '$error\n$stack',
      );
    }
  }

  Future<void> detachRemoteStream() async {
    try {
      _remoteAudioRenderer?.srcObject = null;
      debugPrint('[AudioManager] Remote WebRTC stream detached');
    } catch (error) {
      debugPrint('[AudioManager] Failed to detach remote stream: $error');
    }
  }

  Future<void> setSpeakerphone(bool enabled) async {
    try {
      _isSpeakerOn = enabled;
      _audioRouteInitializedForCall = true;
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

  void resetState() {
    _activeCallId = null;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
  }

  @visibleForTesting
  void resetForTesting() {
    resetState();
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
      final sample =
          frequencies
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
