import UIKit
import Flutter
import CallKit
import PushKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, CXProviderDelegate, PKPushRegistryDelegate {

    private let channelName = "com.sgt.voip.softphone/native_call"
    private var methodChannel: FlutterMethodChannel?
    private var callKitProvider: CXProvider?
    private var callController = CXCallController()
    private var voipRegistry: PKPushRegistry?

    private var activeCallUuids: [String: UUID] = [:]
    private var uuidToOriginalCallUuid: [String: String] = [:]
    private var cachedVoipToken: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        setupMethodChannel(messenger: controller.binaryMessenger)
        setupCallKit()
        setupPushKit()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - MethodChannel Setup
    private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        methodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }

            switch call.method {
            case "showIncomingCall":
                guard let args = call.arguments as? [String: Any],
                      let rawCallUuidStr = args["callUuid"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "callUuid required", details: nil))
                    return
                }
                let callUuidStr = rawCallUuidStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let callerName = args["callerName"] as? String ?? ""
                let callerNumber = args["callerNumber"] as? String ?? ""
                self.reportIncomingCall(callUuidStr: callUuidStr, callerName: callerName, callerNumber: callerNumber) { success in
                    result(success)
                }

            case "dismissIncomingCall":
                guard let args = call.arguments as? [String: Any],
                      let rawCallUuidStr = args["callUuid"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "callUuid required", details: nil))
                    return
                }
                let callUuidStr = rawCallUuidStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.endCall(callUuidStr: callUuidStr)
                result(true)

            case "getPendingCallAction":
                result(nil)

            case "ackCallAction":
                result(true)

            case "getVoipToken":
                result(self.cachedVoipToken)

            case "requestNotificationPermission":
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    result(granted)
                }

            case "canUseFullScreenIntent":
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - CallKit Setup
    private func setupCallKit() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true

        callKitProvider = CXProvider(configuration: config)
        callKitProvider?.setDelegate(self, queue: nil)
    }

    private func reportIncomingCall(
        callUuidStr: String,
        callerName: String,
        callerNumber: String,
        completion: @escaping (Bool) -> Void
    ) {
        let normalized = callUuidStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uuid = UUID(uuidString: normalized) ?? UUID()
        activeCallUuids[normalized] = uuid
        uuidToOriginalCallUuid[uuid.uuidString.lowercased()] = normalized

        let update = CXCallUpdate()
        let displayName = callerName.isEmpty ? "Extension \(callerNumber)" : "\(callerName) (\(callerNumber))"
        update.remoteHandle = CXHandle(type: .generic, value: callerNumber.isEmpty ? "VoIP" : callerNumber)
        update.localizedCallerName = displayName
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        callKitProvider?.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                NSLog("[CallKit] Error reporting incoming call: %@", error.localizedDescription)
                completion(false)
            } else {
                NSLog("[CallKit] Reported incoming call successfully: %@", uuid.uuidString)
                completion(true)
            }
        }
    }

    private func endCall(callUuidStr: String) {
        let normalized = callUuidStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let uuid = activeCallUuids.removeValue(forKey: normalized) else {
            return
        }
        uuidToOriginalCallUuid.removeValue(forKey: uuid.uuidString.lowercased())
        callKitProvider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    }

    // MARK: - CXProviderDelegate
    func providerDidReset(_ provider: CXProvider) {
        activeCallUuids.removeAll()
        uuidToOriginalCallUuid.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuidKey = action.callUUID.uuidString.lowercased()
        let resolvedUuid = uuidToOriginalCallUuid[uuidKey] ?? uuidKey
        NSLog("[CallKit] User answered call %@", resolvedUuid)
        methodChannel?.invokeMethod("onCallAction", arguments: ["action": "answer", "callUuid": resolvedUuid])
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuidKey = action.callUUID.uuidString.lowercased()
        let resolvedUuid = uuidToOriginalCallUuid[uuidKey] ?? uuidKey
        NSLog("[CallKit] User ended/declined call %@", resolvedUuid)
        methodChannel?.invokeMethod("onCallAction", arguments: ["action": "decline", "callUuid": resolvedUuid])
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("[CallKit] Audio session activated")
        methodChannel?.invokeMethod("onAudioSessionState", arguments: ["active": true])
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("[CallKit] Audio session deactivated")
        methodChannel?.invokeMethod("onAudioSessionState", arguments: ["active": false])
    }

    // MARK: - PushKit Setup
    private func setupPushKit() {
        voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
    }

    // MARK: - PKPushRegistryDelegate
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        let maskedToken = token.count > 10 ? "\(token.prefix(4))...\(token.suffix(4))" : "***"
        NSLog("[PushKit] VoIP push token received: %@", maskedToken)
        self.cachedVoipToken = token
        methodChannel?.invokeMethod("onVoipToken", arguments: ["token": token])
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        NSLog("[PushKit] VoIP push token invalidated")
        self.cachedVoipToken = nil
        methodChannel?.invokeMethod("onVoipTokenInvalidated", arguments: nil)
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        let dict = payload.dictionaryPayload
        let action = dict["action"] as? String ?? "incoming_call"

        // Handle remote cancel without reporting a new call
        if action == "cancel_call" {
            if let callUuid = dict["call_uuid"] as? String {
                NSLog("[PushKit] Received remote cancel for call UUID: %@", callUuid)
                self.endCall(callUuidStr: callUuid)
                methodChannel?.invokeMethod("onCallAction", arguments: [
                    "action": "cancel",
                    "callUuid": callUuid
                ])
            }
            completion()
            return
        }

        // Check for stale/expired push
        if let timestamp = dict["timestamp"] as? Double {
            let age = Date().timeIntervalSince1970 - timestamp
            if age > 30.0 {
                NSLog("[PushKit] Ignoring stale VoIP push (age: %.1fs)", age)
                completion()
                return
            }
        }

        let rawCallUuid = dict["call_uuid"] as? String ?? ""
        let callUuid = rawCallUuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !callUuid.isEmpty else {
            NSLog("[PushKit] Push payload missing call_uuid, ignoring")
            completion()
            return
        }

        // Deduplicate incoming call pushes
        if activeCallUuids[callUuid] != nil {
            NSLog("[PushKit] Incoming call already active for %@, ignoring duplicate push", callUuid)
            completion()
            return
        }

        let callerName = dict["caller_display_name"] as? String ?? ""
        let callerNumber = dict["caller_extension"] as? String ?? ""

        // iOS 13+ requirement: MUST report new incoming call to CallKit synchronously/immediately
        reportIncomingCall(callUuidStr: callUuid, callerName: callerName, callerNumber: callerNumber) { _ in
            completion()
        }

        // Notify Flutter engine
        methodChannel?.invokeMethod("onCallAction", arguments: [
            "action": "incoming_push",
            "callUuid": callUuid,
            "callerName": callerName,
            "callerNumber": callerNumber,
        ])
    }
}
