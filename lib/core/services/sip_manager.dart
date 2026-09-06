import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';
import '../constants/app_constants.dart';
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

  // WebRTC Observability & Diagnostic metrics
  Timer? _statsTimer;
  bool _forceRelayOnly = false;
  bool _diagnosticLogging = false;
  List<Map<String, String>> _iceServers = const [];
  int _packetsSent = 0;
  int _packetsReceived = 0;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _packetsLost = 0;
  double _jitter = 0.0;
  double _roundTripTime = 0.0;
  String _selectedCandidatePair = 'Đang thương lượng...';
  String _signalingState = 'new';
  String _iceState = 'new';
  String _peerConnectionState = 'new';
  String _dtlsState = 'new';
  String _negotiatedCodec = 'unknown';
  String _mediaState = 'idle';
  bool _loggedSessionDescriptions = false;

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
  bool get forceRelayOnly => _forceRelayOnly;
  int get packetsSent => _packetsSent;
  int get packetsReceived => _packetsReceived;
  int get bytesSent => _bytesSent;
  int get bytesReceived => _bytesReceived;
  int get packetsLost => _packetsLost;
  double get jitter => _jitter;
  double get roundTripTime => _roundTripTime;
  String get selectedCandidatePair => _selectedCandidatePair;
  String get signalingState => _signalingState;
  String get iceState => _iceState;
  String get peerConnectionState => _peerConnectionState;
  String get dtlsState => _dtlsState;
  String get negotiatedCodec => _negotiatedCodec;
  String get mediaState => _mediaState;

  void setForceRelayOnly(bool value) {
    _forceRelayOnly = value;
    notifyListeners();
  }

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
    _forceRelayOnly = _account!.forceRelayOnly;
    _diagnosticLogging = _account!.diagnosticLogging;
    if (_hasRequiredAccountSettings(_account!)) {
      await register();
    } else {
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Chưa cấu hình tài khoản SIP';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('SipManager', 'didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      if (_currentCall == null &&
          (!_helper.connected ||
              !_helper.registered ||
              _connectionStatus != SipConnectionStatus.online)) {
        _log('SipManager',
            'App resumed & SIP offline -> Triggering immediate register()');
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
    if (!_hasRequiredAccountSettings(acc)) {
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage = 'Thiếu WSS, domain, extension hoặc mật khẩu SIP';
      notifyListeners();
      return;
    }
    _forceRelayOnly = acc.forceRelayOnly;
    _diagnosticLogging = acc.diagnosticLogging;
    _connectionStatus = SipConnectionStatus.connecting;
    _statusMessage = 'Đang kết nối WSS...';
    notifyListeners();

    try {
      final settings = UaSettings();

      // Explicitly set transportType to WS (Fixes Null check operator crash in sip_ua)
      settings.transportType = TransportType.WS;
      settings.webSocketUrl = acc.wssUri;
      // A debug APK is still distributed to real devices by CI, therefore it
      // must not silently trust an invalid certificate. Local developers can
      // opt in explicitly with SGT_ALLOW_BAD_CERTIFICATE=true; release and
      // profile builds always require a valid certificate.
      settings.webSocketSettings.allowBadCertificate =
          kDebugMode && AppConstants.allowBadCertificateInDebug;
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
      settings.iceGatheringTimeout = acc.iceGatheringTimeoutMs;

      // Cấu hình đầy đủ STUN và TURN cho NAT Traversal (4G/Wi-Fi)
      final iceServers = <Map<String, String>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
      if (acc.stunUri.isNotEmpty && !acc.stunUri.contains('google.com')) {
        iceServers.add({'urls': acc.stunUri});
      }
      for (final uri in acc.turnUri
          .split(RegExp(r'[,\n]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)) {
        final turnMap = <String, String>{'urls': uri};
        if (acc.turnUsername.isNotEmpty) {
          turnMap['username'] = acc.turnUsername;
        }
        if (acc.turnPassword.isNotEmpty) {
          turnMap['credential'] = acc.turnPassword;
        }
        iceServers.add(turnMap);
      }

      settings.iceServers = iceServers;
      _iceServers = List.unmodifiable(iceServers);
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
      _diag('SipManager', 'Calling target: $targetUri');

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
      _resetWebRtcDiagnostics();
      _navigateToInCall();
      notifyListeners();

      _log('TIMING', 'Sending SIP INVITE...');
      // 4. Gửi gói tin SIP INVITE WebRTC
      final callOptions = _helper.buildCallOptions(true);
      callOptions['mediaConstraints'] = mediaConstraints;
      _applyIceTransportPolicy(callOptions);
      _helper.call(
        targetUri,
        voiceonly: true,
        customOptions: callOptions,
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
        final answerOptions = _helper.buildCallOptions(true);
        _applyIceTransportPolicy(answerOptions);
        _currentCall!.answer(answerOptions);
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
    _stopWebRtcStatsCollection();
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
    if (_isMuted) {
      _currentCall!.unmute(true, false);
    } else {
      _currentCall!.mute(true, false);
    }
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
    if (_currentCall != null &&
        _currentCall!.state == CallStateEnum.CONFIRMED) {
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
    _stopWebRtcStatsCollection();
  }

  // ── WebRTC Observability Stats Helpers ────────────────────────────────────

  void _startWebRtcStatsCollection() {
    if (_statsTimer?.isActive == true) return;
    Future<void> collect() async {
      final call = _currentCall;
      if (call == null) {
        _stopWebRtcStatsCollection();
        return;
      }
      final pc = call.peerConnection;
      if (pc == null) return;

      try {
        final previousPacketsSent = _packetsSent;
        final previousPacketsReceived = _packetsReceived;
        final reports = await pc.getStats();
        final reportsById = {for (final report in reports) report.id: report};
        _signalingState = '${await pc.getSignalingState()}'.split('.').last;
        _iceState = '${await pc.getIceConnectionState()}'.split('.').last;
        _peerConnectionState =
            '${await pc.getConnectionState()}'.split('.').last;

        if (!_loggedSessionDescriptions) {
          final local = await pc.getLocalDescription();
          final remote = await pc.getRemoteDescription();
          if (local?.sdp != null || remote?.sdp != null) {
            _diag('WEBRTC_SDP',
                'local=${_summarizeSdp(local?.sdp)} remote=${_summarizeSdp(remote?.sdp)}');
            _loggedSessionDescriptions = true;
          }
        }

        for (final report in reports) {
          final vals = report.values;
          if (report.type == 'inbound-rtp' &&
              (vals['kind'] == 'audio' || vals['mediaType'] == 'audio')) {
            _packetsReceived =
                int.tryParse('${vals['packetsReceived']}') ?? _packetsReceived;
            _bytesReceived =
                int.tryParse('${vals['bytesReceived']}') ?? _bytesReceived;
            _packetsLost =
                int.tryParse('${vals['packetsLost']}') ?? _packetsLost;
            _jitter = double.tryParse('${vals['jitter']}') ?? _jitter;
            final codec = reportsById['${vals['codecId']}'];
            if (codec != null) {
              _negotiatedCodec =
                  '${codec.values['mimeType'] ?? codec.values['codec'] ?? 'unknown'}';
            }
          } else if (report.type == 'outbound-rtp' &&
              (vals['kind'] == 'audio' || vals['mediaType'] == 'audio')) {
            _packetsSent =
                int.tryParse('${vals['packetsSent']}') ?? _packetsSent;
            _bytesSent = int.tryParse('${vals['bytesSent']}') ?? _bytesSent;
          } else if (report.type == 'candidate-pair' &&
              vals['state'] == 'succeeded' &&
              (vals['nominated'] == true ||
                  vals['selected'] == true ||
                  (int.tryParse('${vals['bytesSent']}') ?? 0) > 0 ||
                  (int.tryParse('${vals['bytesReceived']}') ?? 0) > 0)) {
            _roundTripTime =
                double.tryParse('${vals['currentRoundTripTime']}') ??
                    _roundTripTime;
            final local = reportsById['${vals['localCandidateId']}'];
            final remote = reportsById['${vals['remoteCandidateId']}'];
            _selectedCandidatePair =
                '${_candidateLabel(local?.values)} <-> ${_candidateLabel(remote?.values)} '
                '(RTT: ${(_roundTripTime * 1000).toStringAsFixed(1)}ms)';
          } else if (report.type == 'transport') {
            _dtlsState = '${vals['dtlsState'] ?? _dtlsState}';
          }
        }

        final sending = _packetsSent > previousPacketsSent;
        final receiving = _packetsReceived > previousPacketsReceived;
        if (sending && receiving) {
          _mediaState = 'flowing';
        } else if (sending || receiving) {
          _mediaState = 'one-way';
        } else if (_packetsSent == 0 && _packetsReceived == 0) {
          _mediaState = 'negotiating';
        } else {
          _mediaState = 'stalled';
        }

        _diag(
            'WEBRTC_STATS',
            '[Call-ID: ${call.id}] '
                'Rcvd: $_packetsReceived pkts (${_bytesReceived}B) | '
                'Sent: $_packetsSent pkts (${_bytesSent}B) | '
                'Lost: $_packetsLost | Jitter: ${_jitter.toStringAsFixed(3)}s | '
                'Codec: $_negotiatedCodec | ICE: $_iceState | DTLS: $_dtlsState | '
                'Media: $_mediaState | Pair: $_selectedCandidatePair');
        notifyListeners();
      } catch (e) {
        _log('WEBRTC_STATS', 'Collection error: $e');
      }
    }

    collect();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => collect(),
    );
  }

  void _stopWebRtcStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  void _resetWebRtcDiagnostics() {
    _packetsSent = 0;
    _packetsReceived = 0;
    _bytesSent = 0;
    _bytesReceived = 0;
    _packetsLost = 0;
    _jitter = 0.0;
    _roundTripTime = 0.0;
    _selectedCandidatePair = 'Đang thương lượng...';
    _signalingState = 'new';
    _iceState = 'new';
    _peerConnectionState = 'new';
    _dtlsState = 'new';
    _negotiatedCodec = 'unknown';
    _mediaState = 'idle';
    _loggedSessionDescriptions = false;
  }

  bool _hasRequiredAccountSettings(SipAccount account) {
    return account.wssUri.trim().isNotEmpty &&
        account.domain.trim().isNotEmpty &&
        account.extension.trim().isNotEmpty &&
        account.password.isNotEmpty;
  }

  void _applyIceTransportPolicy(Map<String, dynamic> options) {
    final existing = options['pcConfig'];
    final pcConfig = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    pcConfig.putIfAbsent('iceServers', () => _iceServers);
    pcConfig['iceTransportPolicy'] = _forceRelayOnly ? 'relay' : 'all';
    options['pcConfig'] = pcConfig;
  }

  void _diag(String tag, String message) {
    if (_diagnosticLogging) {
      _log(tag, message);
    }
  }

  String _candidateLabel(Map<dynamic, dynamic>? values) {
    if (values == null) return 'unknown';
    final type = values['candidateType'] ?? 'unknown';
    final protocol = values['protocol'] ?? '';
    final address = values['address'] ?? values['ip'] ?? '';
    final port = values['port'] ?? '';
    return '$type/$protocol $address:$port'.trim();
  }

  String _summarizeSdp(String? sdp) {
    if (sdp == null || sdp.isEmpty) return 'none';
    return sdp
        .split(RegExp(r'\r?\n'))
        .where((line) =>
            line.startsWith('m=audio') ||
            line.startsWith('a=rtpmap:') ||
            line.startsWith('a=fingerprint:') ||
            line.startsWith('a=candidate:'))
        .join(' | ');
  }

  // ── SipUaHelperListener Callbacks ────────────────────────────────────────

  @override
  void registrationStateChanged(RegistrationState state) {
    _log('TIMING',
        'registrationStateChanged: ${state.state} (cause=${state.cause?.toString()})');
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
        _statusMessage =
            'Đăng ký thất bại (${state.cause?.toString() ?? 'Lỗi'})';
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
      _log('SipManager',
          'Max auto-reconnect attempts reached ($_maxReconnectAttempts).');
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
        _log('SipManager',
            'Auto-reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delaySeconds}s)...');
        register();
      }
    });
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _log('TIMING',
        'callStateChanged: state=${state.state}, origin=${call.direction}, id=${call.id}');
    _currentCall = call;
    _callState = state;

    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _stopCallTimer();
        _resetWebRtcDiagnostics();
        _callDurationSeconds = 0;
        if (call.direction.toUpperCase() == 'INCOMING') {
          _log('TIMING',
              '>>> INCOMING INVITE received! Starting ringtone and navigating to incoming call screen.');
          _audioManager.playRingtone();
          _navigateToIncomingCall();
        }
        break;

      case CallStateEnum.CONNECTING:
        _log('TIMING', 'Call is CONNECTING (ICE/signaling negotiation)');
        _startWebRtcStatsCollection();
        break;

      case CallStateEnum.STREAM:
        final audioTracks = state.stream?.getAudioTracks() ?? [];
        _diag('WEBRTC_MEDIA',
            'Remote stream received: ${audioTracks.length} audio track(s), enabled=${audioTracks.map((track) => track.enabled).toList()}');
        break;

      case CallStateEnum.PROGRESS:
        _log('TIMING',
            'Call is PROGRESS (180/183 Ringing), origin=${call.direction}');
        if (call.direction.toUpperCase() == 'OUTGOING') {
          _audioManager.playRingback();
          _navigateToInCall();
        }
        _startWebRtcStatsCollection();
        break;

      case CallStateEnum.ACCEPTED:
        _log('TIMING', '>>> Call ACCEPTED (200 OK received/sent)');
        _audioManager.stopAll();
        _startCallTimer();
        _startWebRtcStatsCollection();
        _navigateToInCall();
        break;

      case CallStateEnum.CONFIRMED:
        _log('TIMING', '>>> Call CONFIRMED (ACK received/dialog established)');
        _audioManager.stopAll();
        _startCallTimer();
        _startWebRtcStatsCollection();
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
        _log('TIMING',
            '>>> Call ${state.state} (origin=${call.direction}, cause=${state.cause})');
        _audioManager.stopAll();
        _stopCallTimer();
        _stopWebRtcStatsCollection();
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
    _diag('SipManager', 'New SIP message received: ${msg.request.body}');
  }

  @override
  void onNewNotify(Notify ntf) {
    _diag('SipManager', 'New SIP notify received: ${ntf.request?.body}');
  }

  // ── Navigation Routing Helpers ───────────────────────────────────────────

  CallScreenState _callScreenState = CallScreenState.none;
  CallScreenState get callScreenState => _callScreenState;

  void _navigateToIncomingCall() {
    _log('SipManager',
        'Attempting navigation to incoming call screen. Current state: $_callScreenState');
    if (_callScreenState == CallScreenState.none) {
      _callScreenState = CallScreenState.incoming;
      navigatorKey?.currentState?.pushNamed('/incoming').then((_) {
        _log('SipManager', 'Incoming call screen popped/closed');
        _callScreenState = CallScreenState.none;
      });
    } else {
      _log('SipManager',
          'Skip navigating to incoming screen: already in state $_callScreenState');
    }
  }

  void _navigateToInCall() {
    _log('SipManager',
        'Attempting navigation to in-call screen. Current state: $_callScreenState');
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
      _log('SipManager',
          'Skip navigating to in-call screen: already in state $_callScreenState');
    }
  }

  void _navigateBackToDialpad() {
    _log('SipManager',
        'Navigating back to dialpad from state: $_callScreenState');
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
