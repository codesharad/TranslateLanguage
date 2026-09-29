import Flutter
import UIKit
import PushKit
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "PcmPlayerPlugin") {
      PcmPlayerPlugin.register(with: registrar)
    }

    let voip = PKPushRegistry(queue: .main)
    voip.delegate = self
    voip.desiredPushTypes = [.voIP]
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: "voip_token")
    print("[voip] token \(token)")
  }

  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    let info = payload.dictionaryPayload
    let callId = (info["callId"] as? String) ?? (info["uuid"] as? String) ?? UUID().uuidString
    let name = (info["callerName"] as? String) ?? "Incoming call"
    let handle = (info["handle"] as? String) ?? name
    let cfg = CXProviderConfiguration()
    cfg.supportsVideo = false
    cfg.maximumCallsPerCallGroup = 1
    let provider = CXProvider(configuration: cfg)
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.localizedCallerName = name
    update.hasVideo = false
    provider.reportNewIncomingCall(with: UUID(uuidString: callId) ?? UUID(), update: update) { _ in
      completion()
    }
  }
}
