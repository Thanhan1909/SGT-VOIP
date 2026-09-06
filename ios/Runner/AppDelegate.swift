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
                      let callUuidStr = args["callUuid"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "callUuid required", details: nil))
                    return
                }
                let callerName = args["callerName"] as? String ?? ""
                let callerNumber = args["callerNumber"] as? String ?? ""
                self.reportIncomingCall(callUuidStr: callUuidStr, callerName: callerName, callerNumber: callerNumber) { success in
                    result(success)
                }

            case "dismissIncomingCall":
                guard let args = call.arguments as? [String: Any],
                      let callUuidStr = args["callUuid"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "callUuid required", details: nil))
                    return
                }
                self.endCall(callUuidStr: callUuidStr)
                result(true)

            case "getVoipToken":
                result(self.cachedVoipToken)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - CallKit Setup
    private func setupCallKit() {
        let config = CXProviderConfiguration(localizedName: "SGT Softphone")
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
        let uuid = UUID(uuidString: callUuidStr) ?? UUID()
        activeCallUuids[callUuidStr] = uuid

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
        guard let uuid = activeCallUuids.removeValue(forKey: callUuidStr) else {
            return
        }
        callKitProvider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    }

    // MARK: - CXProviderDelegate
    func providerDidReset(_ provider: CXProvider) {
        activeCallUuids.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuidStr = action.callUUID.uuidString
        NSLog("[CallKit] User answered call %@", uuidStr)
        methodChannel?.invokeMethod("onCallAction", arguments: ["action": "answer", "callUuid": uuidStr])
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuidStr = action.callUUID.uuidString
        NSLog("[CallKit] User ended/declined call %@", uuidStr)
        methodChannel?.invokeMethod("onCallAction", arguments: ["action": "decline", "callUuid": uuidStr])
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("[CallKit] Audio session activated")
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("[CallKit] Audio session deactivated")
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
        NSLog("[PushKit] VoIP push token received: %@", token)
        self.cachedVoipToken = token
        methodChannel?.invokeMethod("onVoipToken", arguments: ["token": token])
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
        NSLog("[PushKit] Received incoming VoIP push payload: %@", dict)

        let callUuid = dict["call_uuid"] as? String ?? UUID().uuidString
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
