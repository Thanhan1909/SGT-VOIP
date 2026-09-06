import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Abstraction for platform audio routing to allow unit testing and safe decoupled execution.
abstract class AudioRouteAdapter {
  Future<void> setSpeakerphoneOn(bool enabled);
}

/// Default implementation delegating to [Helper.setSpeakerphoneOn] on mobile platforms.
class DefaultAudioRouteAdapter implements AudioRouteAdapter {
  const DefaultAudioRouteAdapter();

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {
    if (!kIsWeb) {
      await Helper.setSpeakerphoneOn(enabled);
    }
  }
}
