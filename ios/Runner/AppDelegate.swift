import Flutter
import AVFoundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let audioBridge = DartlingvoAudioBridge()
  private var audioChannelsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    DispatchQueue.main.async { [weak self] in
      self?.configureAudioBridgeIfPossible()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureAudioBridgeIfPossible()
  }

  private func configureAudioBridgeIfPossible() {
    guard !audioChannelsConfigured else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let audioChannel = FlutterMethodChannel(
      name: "dartlingvo/audio",
      binaryMessenger: controller.binaryMessenger
    )
    audioChannel.setMethodCallHandler(audioBridge.handle)
    audioChannelsConfigured = true
    print("[DartlingvoAudioBridge] configured")
  }
}

final class DartlingvoAudioBridge: NSObject {
  private var audioPlayer: AVAudioPlayer?
  private var currentPath: String?
  private var currentDurationMs: Int = 0
  private var isPaused = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "dartlingvo_audio", message: "Missing path", details: nil))
        return
      }

      do {
        try configureSession()
        try play(path: path)
        result(currentDurationMs)
      } catch {
        result(FlutterError(code: "dartlingvo_audio", message: error.localizedDescription, details: nil))
      }

    case "pause":
      pause()
      result(nil)

    case "stop":
      stop()
      result(nil)

    case "duration":
      result(currentDurationMs)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
  }

  private func play(path: String) throws {
    let url = URL(fileURLWithPath: path)
    let playableURL = try preparedPlayableURL(from: url)
    let needsReload = currentPath != path || audioPlayer == nil

    if needsReload {
      let data = try Data(contentsOf: playableURL, options: .mappedIfSafe)
      let player = try AVAudioPlayer(data: data)
      player.prepareToPlay()
      audioPlayer = player
      currentDurationMs = Int((player.duration * 1000).rounded())
      print("[DartlingvoAudioBridge] opened file path=\(path) playablePath=\(playableURL.path) durationMs=\(currentDurationMs)")
    }

    currentPath = path

    guard let player = audioPlayer else {
      throw NSError(
        domain: "dartlingvo_audio",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Audio player unavailable"]
      )
    }

    if isPaused {
      isPaused = false
      if !player.isPlaying {
        player.play()
      }
      print("[DartlingvoAudioBridge] resumed")
      return
    }

    if player.isPlaying {
      player.stop()
    }

    player.currentTime = 0
    if !player.play() {
      throw NSError(
        domain: "dartlingvo_audio",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Audio playback failed to start"]
      )
    }
    print("[DartlingvoAudioBridge] playback started path=\(playableURL.path)")
  }

  private func preparedPlayableURL(from url: URL) throws -> URL {
    guard url.pathExtension.lowercased() == "wav" else {
      return url
    }

    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard let metadata = Self.parseWaveMetadata(data) else {
      return url
    }

    guard metadata.formatCode == 0x0055 else {
      return url
    }

    let cacheURL = try Self.convertedAudioURL(for: url, fileExtension: "mp3")
    if !FileManager.default.fileExists(atPath: cacheURL.path) {
      let payload = data.subdata(in: metadata.dataRange)
      try payload.write(to: cacheURL, options: .atomic)
      print("[DartlingvoAudioBridge] extracted MPEG Layer 3 payload path=\(cacheURL.path) bytes=\(payload.count)")
    }

    return cacheURL
  }

  private static func convertedAudioURL(for sourceURL: URL, fileExtension: String) throws -> URL {
    let fileManager = FileManager.default
    let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let outputDirectory = cachesURL.appendingPathComponent("dartlingvo_audio", isDirectory: true)
    if !fileManager.fileExists(atPath: outputDirectory.path) {
      try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let hashed = String(sourceURL.path.hashValue, radix: 16)
    return outputDirectory.appendingPathComponent("\(baseName)_\(hashed).\(fileExtension)")
  }

  private struct WaveMetadata {
    let formatCode: UInt16
    let dataRange: Range<Int>
  }

  private static func parseWaveMetadata(_ data: Data) -> WaveMetadata? {
    guard data.count >= 12 else { return nil }
    guard data.prefix(4) == Data("RIFF".utf8) else { return nil }
    guard data.subdata(in: 8..<12) == Data("WAVE".utf8) else { return nil }

    var offset = 12
    var formatCode: UInt16?
    var dataRange: Range<Int>?

    while offset + 8 <= data.count {
      guard let chunkID = String(data: data.subdata(in: offset..<offset + 4), encoding: .ascii) else {
        break
      }

      let chunkSize = Int(readUInt32LE(data, offset + 4))
      let payloadOffset = offset + 8
      let payloadEnd = payloadOffset + chunkSize
      if payloadEnd > data.count {
        break
      }

      if chunkID == "fmt " && chunkSize >= 2 {
        formatCode = readUInt16LE(data, payloadOffset)
      } else if chunkID == "data" {
        dataRange = payloadOffset..<payloadEnd
      }

      if formatCode != nil && dataRange != nil {
        break
      }

      offset = payloadEnd + (chunkSize % 2)
    }

    guard let formatCode, let dataRange else {
      return nil
    }

    return WaveMetadata(formatCode: formatCode, dataRange: dataRange)
  }

  private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
    let b0 = UInt16(data[offset])
    let b1 = UInt16(data[offset + 1]) << 8
    return b0 | b1
  }

  private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1]) << 8
    let b2 = UInt32(data[offset + 2]) << 16
    let b3 = UInt32(data[offset + 3]) << 24
    return b0 | b1 | b2 | b3
  }

  private func pause() {
    guard let player = audioPlayer, player.isPlaying else {
      return
    }
    player.pause()
    isPaused = true
    print("[DartlingvoAudioBridge] paused")
  }

  private func stop() {
    audioPlayer?.stop()
    isPaused = false
    print("[DartlingvoAudioBridge] stopped")
  }
}
