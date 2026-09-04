import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../data/models/sip_account.dart';
import 'audio_manager.dart';

void _log(String tag, String msg) {
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[$ts][$tag] $msg');
}

enum CallScreenState {
  none,
  incoming,
  inCall,
}

enum SipConnectionStatus {
  offline,
  connecting,
  registering,
  online,
  error,
}

class SipManager extends ChangeNotifier
    with WidgetsBindingObserver
    implements SipUaHelperListener {
  static final SipManager _instance = SipManager._internal();
  factory SipManager() => _instance;
  SipManager._internal();

  final SIPUAHelper _helper = SIPUAHelper();
  final AudioManager _audioManager = AudioManager();

  SipAccount? _account;
  SipConnectionStatus _connectionStatus = SipConnectionStatus.offline;
  String _statusMessage = 'Chưa kết nối';

  Call? _currentCall;
  CallState? _callState;
  bool _isMuted = false;
  bool _isOnHold = false;
  int _callDurationSeconds = 0;
  Timer? _callTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  bool _isReconfiguring = false;

  // Global navigator key for navigating to incoming / in-call screens
  GlobalKey<NavigatorState>? navigatorKey;

  // Getters
  SIPUAHelper get helper => _helper;
  SipAccount? get account => _account;
  SipConnectionStatus get connectionStatus => _connectionStatus;
  String get statusMessage => _statusMessage;
  Call? get currentCall => _currentCall;
  CallState? get callState => _callState;
  bool get isMuted => _isMuted;
  bool get isOnHold => _isOnHold;
  bool get isSpeakerOn => _audioManager.isSpeakerOn;
  int get callDurationSeconds => _callDurationSeconds;

  String get formattedDuration {
    final mins = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    navigatorKey = navKey;
    WidgetsBinding.instance.addObserver(this);
    _helper.addSipUaHelperListener(this);
    await _audioManager.init();
    _account = await SipAccount.loadFromPrefs();
    await register();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('SipManager', 'didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      if (_currentCall == null &&
          (!_helper.connected ||
              !_helper.registered ||
              _connectionStatus != SipConnectionStatus.online)) {
        _log('SipManager', 'App resumed & SIP offline -> Triggering immediate register()');
        _reconnectAttempts = 0;
        register();
      }
    }
  }

  Future<void> register({SipAccount? newAccount}) async {
    if (newAccount != null) {
      _account = newAccount;
      _reconnectAttempts = 0;
      await _account!.saveToPrefs();
    }

    _account ??= await SipAccount.loadFromPrefs();

    final acc = _account!;
    _connectionStatus = SipConnectionStatus.connecting;
    _statusMessage = 'Đang kết nối WSS...';
    notifyListeners();

    try {
      final settings = UaSettings();

      // Explicitly set transportType to WS (Fixes Null check operator crash in sip_ua)
      settings.transportType = TransportType.WS;
      settings.webSocketUrl = acc.wssUri;
      settings.webSocketSettings.allowBadCertificate = true;
      settings.webSocketSettings.transport_scheme =
          acc.wssUri.startsWith('wss') ? 'wss' : 'ws';
      settings.uri = 'sip:${acc.extension}@${acc.domain}';
      settings.authorizationUser = acc.extension;
      settings.password = acc.password;
      settings.realm = 'asterisk';
      settings.displayName =
          acc.displayName.isNotEmpty ? acc.displayName : acc.extension;
      settings.userAgent = 'Flutter SGT VoIP Softphone / Asterisk 20';
      settings.register = true;
      // 25s auto-refresh registration via sip_ua registrator (fires at 20s < 32s Asterisk idle timeout)
      settings.register_expires = 25;
      settings.iceGatheringTimeout = 500;

      // Configure STUN ICE Servers for NAT Traversal (TURN omitted: port 3478 is unreachable from WAN)
      final iceServers = <Map<String, String>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
      if (acc.stunUri.isNotEmpty && !acc.stunUri.contains('google.com')) {
        iceServers.add({'urls': acc.stunUri});
      }

      settings.iceServers = iceServers;
      settings.dtmfMode = DtmfMode.RFC2833;

      if (_helper.connected || _helper.registered) {
        _isReconfiguring = true;
        _reconnectTimer?.cancel();
        _helper.stop();
        await Future.delayed(const Duration(milliseconds: 150));
        _isReconfiguring = false;
      }

      _helper.start(settings);
    } catch (e) {
      debugPrint('[SipManager] Register error: $e');
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage = 'Lỗi kết nối: $e';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<void> unregister() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _isReconfiguring = true;
      _helper.unregister(true);
      _helper.stop();
      _isReconfiguring = false;
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Đã ngắt kết nối';
      notifyListeners();
    } catch (e) {
      debugPrint('[SipManager] Unregister error: $e');
    }
  }

  // ── Call Actions ──────────────────────────────────────────────────────────

  Future<void> makeCall(String targetNumber) async {
    final cleanNumber = targetNumber.trim();
    if (cleanNumber.isEmpty) return;

    if (_connectionStatus != SipConnectionStatus.online) {
      _log('SipManager', 'Cannot call: SIP is not online');
      return;
    }

    try {
      _log('TIMING', '>>> makeCall initiated for $cleanNumber');
      // 1. Request Microphone Runtime Permission on iOS/Android
      if (!kIsWeb) {
        var micStatus = await Permission.microphone.status;
        if (!micStatus.isGranted) {
          micStatus = await Permission.microphone.request();
          if (!micStatus.isGranted) {
            _log('SipManager', 'Microphone permission denied');
            _statusMessage = 'Cần cấp quyền Microphone để gọi';
            notifyListeners();
            return;
          }
        }
      }

      final targetUri = 'sip:$cleanNumber@${_account!.domain}';
      _log('SipManager', 'Calling target: $targetUri');

      // 2. Strict Voice-only constraints with Google WebRTC DSP filters
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'mandatory': {
            'googEchoCancellation': true,
            'googAutoGainControl': true,
            'googNoiseSuppression': true,
            'googHighpassFilter': true,
          },
          'optional': <dynamic>[],
        },
        'video': false,
      };

      // 3. Reset timer and optimistic UI: Chuyển màn hình đàm thoại tức thì (0ms Delay)
      _stopCallTimer();
      _callDurationSeconds = 0;
      _navigateToInCall();
      notifyListeners();

      _log('TIMING', 'Sending _helper.call($targetUri)...');
      // 4. Gửi gói tin SIP INVITE WebRTC
      _helper.call(
        targetUri,
        voiceonly: true,
        customOptions: {'mediaConstraints': mediaConstraints},
      );
    } catch (e, stack) {
      _log('SipManager', 'Error during makeCall: $e\n$stack');
    }
  }

  Future<void> answerCall() async {
    if (_currentCall != null) {
      try {
        _log('TIMING', '>>> answerCall clicked by user');
        if (!kIsWeb) {
          var micStatus = await Permission.microphone.status;
          if (!micStatus.isGranted) {
            micStatus = await Permission.microphone.request();
            if (!micStatus.isGranted) {
              _log('SipManager', 'Microphone permission denied');
              return;
            }
          }
        }
        _audioManager.stopAll();
        _log('TIMING', 'Sending _currentCall!.answer()...');
        _currentCall!.answer(_helper.buildCallOptions(true));
        _startCallTimer();
        notifyListeners();
      } catch (e, stack) {
        _log('SipManager', 'Error during answerCall: $e\n$stack');
      }
    }
  }

  void hangupCall() {
    _audioManager.stopAll();
    _stopCallTimer();
    _callDurationSeconds = 0;
    if (_currentCall != null) {
      try {
        _currentCall!.hangup();
      } catch (e) {
        debugPrint('[SipManager] Hangup error: $e');
      }
    }
    _currentCall = null;
    _callState = null;
    notifyListeners();
  }

  void toggleMute() {
    if (_currentCall == null) return;
    _isMuted = !_isMuted;
    _currentCall!.mute(true, false); // mute audio
    notifyListeners();
  }

  void toggleHold() {
    if (_currentCall == null) return;
    _isOnHold = !_isOnHold;
    if (_isOnHold) {
      _currentCall!.hold();
    } else {
      _currentCall!.unhold();
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    _audioManager.toggleSpeakerphone();
    notifyListeners();
  }

  void sendDTMF(String tone) {
    if (_currentCall != null && _currentCall!.state == CallStateEnum.CONFIRMED) {
      try {
        _currentCall!.sendDTMF(tone);
      } catch (e) {
        debugPrint('[SipManager] sendDTMF error: $e');
      }
    }
  }

  /// Đá luồng / Chuyển cuộc gọi (Hỗ trợ cả SIP REFER và DTMF ##)
  Future<bool> transferCall(String targetExtension) async {
    if (_currentCall == null || targetExtension.trim().isEmpty) return false;
    final target = targetExtension.trim();
    final targetUri =
        target.contains('@') ? target : '$target@${_account!.domain}';

    debugPrint('[SipManager] Transferring call to: $targetUri');
    try {
      // 1. Chuyển cuộc gọi chuẩn SIP REFER
      _currentCall!.refer('sip:$targetUri');
      return true;
    } catch (e) {
      debugPrint('[SipManager] SIP REFER failed ($e), falling back to DTMF ##');
      try {
        // 2. Dự phòng bằng DTMF Feature ##
        _currentCall!.sendDTMF('##$target');
        return true;
      } catch (dtmfErr) {
        debugPrint('[SipManager] DTMF Transfer error: $dtmfErr');
        return false;
      }
    }
  }

  void transferViaDTMF(String targetExtension) {
    if (_currentCall != null) {
      _currentCall!.sendDTMF('##${targetExtension.trim()}');
    }
  }

  // ── Call Timer Helpers ───────────────────────────────────────────────────

  void _startCallTimer() {
    if (_callTimer != null && _callTimer!.isActive) {
      return;
    }
    _stopCallTimer();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callDurationSeconds = 0;
  }

  // ── SipUaHelperListener Callbacks ────────────────────────────────────────

  @override
  void registrationStateChanged(RegistrationState state) {
    _log('TIMING', 'registrationStateChanged: ${state.state} (cause=${state.cause?.toString()})');
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _reconnectAttempts = 0;
        _connectionStatus = SipConnectionStatus.online;
        _statusMessage = 'Đã đăng ký (${_account?.extension})';
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        break;
      case RegistrationStateEnum.UNREGISTERED:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Chưa đăng ký';
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _connectionStatus = SipConnectionStatus.error;
        _statusMessage = 'Đăng ký thất bại (${state.cause?.toString() ?? 'Lỗi'})';
        _scheduleReconnect();
        break;
      case RegistrationStateEnum.NONE:
      default:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Ngoại tuyến';
        break;
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_currentCall != null || _isReconfiguring) return;
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log('SipManager', 'Max auto-reconnect attempts reached ($_maxReconnectAttempts).');
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage = 'Mất kết nối. Chạm biểu tượng để thử lại.';
      notifyListeners();
      return;
    }

    final delaySeconds = [2, 5, 10][_reconnectAttempts % 3];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_connectionStatus != SipConnectionStatus.online &&
          _currentCall == null &&
          !_isReconfiguring) {
        _reconnectAttempts++;
        _log('SipManager', 'Auto-reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delaySeconds}s)...');
        register();
      }
    });
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _log('TIMING', 'callStateChanged: state=${state.state}, origin=${call.direction}, id=${call.id}');
    _currentCall = call;
    _callState = state;

    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _stopCallTimer();
        _callDurationSeconds = 0;
        if (call.direction.toUpperCase() == 'INCOMING') {
          _log('TIMING', '>>> INCOMING INVITE received! Starting ringtone and navigating to incoming call screen.');
          _audioManager.playRingtone();
          _navigateToIncomingCall();
        }
        break;

      case CallStateEnum.CONNECTING:
        _log('TIMING', 'Call is CONNECTING (ICE/signaling negotiation)');
        break;

      case CallStateEnum.PROGRESS:
        _log('TIMING', 'Call is PROGRESS (180/183 Ringing), origin=${call.direction}');
        if (call.direction.toUpperCase() == 'OUTGOING') {
          _audioManager.playRingback();
          _navigateToInCall();
        }
        break;

      case CallStateEnum.ACCEPTED:
        _log('TIMING', '>>> Call ACCEPTED (200 OK received/sent)');
        _audioManager.stopAll();
        _startCallTimer();
        _navigateToInCall();
        break;

      case CallStateEnum.CONFIRMED:
        _log('TIMING', '>>> Call CONFIRMED (ACK received/dialog established)');
        _audioManager.stopAll();
        _startCallTimer();
        _navigateToInCall();
        break;

      case CallStateEnum.HOLD:
        _isOnHold = true;
        break;

      case CallStateEnum.UNHOLD:
        _isOnHold = false;
        break;

      case CallStateEnum.MUTED:
        _isMuted = true;
        break;

      case CallStateEnum.UNMUTED:
        _isMuted = false;
        break;

      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _log('TIMING', '>>> Call ${state.state} (origin=${call.direction}, cause=${state.cause})');
        _audioManager.stopAll();
        _stopCallTimer();
        _callDurationSeconds = 0;
        _currentCall = null;
        _callState = null;
        _navigateBackToDialpad();
        break;

      default:
        break;
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    _log('TIMING', 'transportStateChanged: ${state.state}');
    if (_isReconfiguring) return;
    if (state.state == TransportStateEnum.CONNECTED) {
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connectionStatus = SipConnectionStatus.registering;
      _statusMessage = 'Đang đăng ký SIP...';
    } else if (state.state == TransportStateEnum.DISCONNECTED) {
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Mất kết nối WSS (Đang thử kết nối lại...)';
      _scheduleReconnect();
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    _log('SipManager', 'New SIP message received: ${msg.request.body}');
  }

  @override
  void onNewNotify(Notify ntf) {
    _log('SipManager', 'New SIP notify received: ${ntf.request?.body}');
  }



  // ── Navigation Routing Helpers ───────────────────────────────────────────

  CallScreenState _callScreenState = CallScreenState.none;
  CallScreenState get callScreenState => _callScreenState;

  void _navigateToIncomingCall() {
    _log('SipManager', 'Attempting navigation to incoming call screen. Current state: $_callScreenState');
    if (_callScreenState == CallScreenState.none) {
      _callScreenState = CallScreenState.incoming;
      navigatorKey?.currentState?.pushNamed('/incoming').then((_) {
        _log('SipManager', 'Incoming call screen popped/closed');
        _callScreenState = CallScreenState.none;
      });
    } else {
      _log('SipManager', 'Skip navigating to incoming screen: already in state $_callScreenState');
    }
  }

  void _navigateToInCall() {
    _log('SipManager', 'Attempting navigation to in-call screen. Current state: $_callScreenState');
    if (_callScreenState == CallScreenState.incoming) {
      _log('SipManager', 'Replacing incoming call screen with in-call screen');
      _callScreenState = CallScreenState.inCall;
      navigatorKey?.currentState?.pushReplacementNamed('/in_call').then((_) {
        _log('SipManager', 'In-call screen popped/closed');
        _callScreenState = CallScreenState.none;
      });
    } else if (_callScreenState == CallScreenState.none) {
      _log('SipManager', 'Pushing in-call screen (direct/outgoing)');
      _callScreenState = CallScreenState.inCall;
      navigatorKey?.currentState?.pushNamed('/in_call').then((_) {
        _log('SipManager', 'In-call screen popped/closed');
        _callScreenState = CallScreenState.none;
      });
    } else {
      _log('SipManager', 'Skip navigating to in-call screen: already in state $_callScreenState');
    }
  }

  void _navigateBackToDialpad() {
    _log('SipManager', 'Navigating back to dialpad from state: $_callScreenState');
    if (_callScreenState != CallScreenState.none) {
      _callScreenState = CallScreenState.none;
      try {
        navigatorKey?.currentState?.popUntil((route) => route.isFirst);
      } catch (e) {
        _log('SipManager', 'Navigate back error: $e');
      }
    }
  }
}
