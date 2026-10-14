import Flutter
import Foundation

/// Flutter ↔ 实时活动。Dart 端每次快照变化时调用 sync，传进行中的计时。
enum LiveActivityBridge {
  static func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "honghong/live_activity", binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      guard call.method == "sync" else { result(FlutterMethodNotImplemented); return }
      let args = call.arguments as? [String: Any] ?? [:]
      let baby = args["baby"] as? String ?? "宝宝"
      let raw = args["sessions"] as? [[String: Any]] ?? []
      let sessions: [(CareKind, Date)] = raw.compactMap {
        guard let k = CareKind(rawValue: $0["type"] as? String ?? ""),
              let ms = ($0["start"] as? NSNumber)?.doubleValue else { return nil }
        return (k, Date(timeIntervalSince1970: ms / 1000))
      }
      #if canImport(ActivityKit)
      Task {
        await HHLive.sync(baby: baby, sessions: sessions)
        result(true)
      }
      #else
      result(false)
      #endif
    }
  }
}
