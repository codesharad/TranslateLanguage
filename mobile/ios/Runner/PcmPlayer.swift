import AVFoundation
import Flutter

/// Plays 16 kHz PCM16 into the CallKit-activated voiceChat session.
final class PcmPlayerPlugin: NSObject, FlutterPlugin {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var converterFormat: AVAudioFormat?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "translatelanguage/pcm_player",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(PcmPlayerPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let args = call.arguments as? [String: Any]
      start(sampleRate: args?["sampleRate"] as? Double ?? 16000)
      result(nil)
    case "write":
      if let bytes = (call.arguments as? [String: Any])?["bytes"] as? FlutterStandardTypedData {
        enqueue(bytes.data)
      }
      result(nil)
    case "flush":
      player?.stop()
      player?.play()
      result(nil)
    case "setSpeaker":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? true
      setSpeaker(on)
      result(nil)
    case "stop":
      player?.stop()
      engine?.stop()
      player = nil
      engine = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(sampleRate: Double) {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let floatFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: floatFormat)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
      )
      try session.setPreferredSampleRate(sampleRate)
      try session.setPreferredIOBufferDuration(0.02)
      try session.setActive(true)
      try engine.start()
      player.play()
    } catch {
      print("[pcm] audio engine \(error)")
    }
    self.engine = engine
    self.player = player
    self.converterFormat = floatFormat
  }

  private func setSpeaker(_ on: Bool) {
    let session = AVAudioSession.sharedInstance()
    try? session.overrideOutputAudioPort(on ? .speaker : .none)
  }

  private func enqueue(_ data: Data) {
    guard let format = converterFormat, let player else { return }
    let sampleCount = data.count / 2
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    data.withUnsafeBytes { raw in
      let src = raw.bindMemory(to: Int16.self)
      let dst = buffer.floatChannelData![0]
      for i in 0..<sampleCount {
        dst[i] = Float(src[i]) / 32768.0
      }
    }
    player.scheduleBuffer(buffer, completionHandler: nil)
  }
}
