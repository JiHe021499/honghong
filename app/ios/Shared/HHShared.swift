// 哄哄：App 与小组件扩展共用（两个 target 都编译这个文件）。
// 数据通过 App Group 的 UserDefaults 交换：
//  - App（Flutter，home_widget 插件）写快照 hh_*，键和安卓小部件完全一样；
//  - 小组件 / 控制中心 / 实时活动按钮把动作追加到待处理队列 hh_pending，并乐观地改快照让界面立即反应；
//  - App 启动和回前台时按时间顺序执行队列（与安卓 runQuickAction 同一套规则），写入数据库并标记待同步。
import Foundation
import WidgetKit
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

enum HH {
  static let appGroup = "group.com.honghong.honghong"
  static let pendingKey = "hh_pending"
  static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

  static func hm(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: d)
  }

  static func reloadAll() {
    WidgetCenter.shared.reloadAllTimelines()
    if #available(iOS 18.0, *) {
      ControlCenter.shared.reloadAllControls()
    }
  }
}

enum CareKind: String, CaseIterable, Codable, Hashable {
  case feed, sleep, burp, diaper

  var label: String {
    switch self {
    case .feed: return "喂奶"
    case .sleep: return "睡觉"
    case .burp: return "拍嗝"
    case .diaper: return "换尿布"
    }
  }

  var running: String {
    switch self {
    case .feed: return "喂奶中"
    case .sleep: return "睡觉中"
    case .burp: return "拍嗝中"
    case .diaper: return "换尿布"
    }
  }

  var icon: String { "care_\(rawValue)" }
  var isTimed: Bool { self != .diaper }
  static let timed: [CareKind] = [.feed, .sleep, .burp]
}

/// App 写入的快照（键与安卓 widgetData() 相同；时间为毫秒时间戳，0 表示没有）
struct HHSnapshot {
  var baby: String
  var starts: [CareKind: Date]
  var feedLast: String
  var sleepWoke: String
  var diaperLast: String
  var done: String

  static func load(_ d: UserDefaults = HH.defaults) -> HHSnapshot {
    func date(_ k: String) -> Date? {
      let ms = (d.object(forKey: k) as? NSNumber)?.doubleValue ?? 0
      return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
    }
    var starts: [CareKind: Date] = [:]
    for k in CareKind.timed { if let s = date("hh_\(k.rawValue)_start") { starts[k] = s } }
    return HHSnapshot(
      baby: d.string(forKey: "hh_baby") ?? "宝宝",
      starts: starts,
      feedLast: d.string(forKey: "hh_feed_last") ?? "",
      sleepWoke: d.string(forKey: "hh_sleep_woke") ?? "",
      diaperLast: d.string(forKey: "hh_diaper_last") ?? "",
      done: d.string(forKey: "hh_done") ?? ""
    )
  }

  /// 最早开始的进行中计时（与安卓"置顶"规则一致）
  var primary: (kind: CareKind, start: Date)? {
    starts.min { $0.value < $1.value }.map { ($0.key, $0.value) }
  }

  var subtitle: String {
    if let p = primary { return "\(HH.hm(p.start)) 开始" }
    var parts = [feedLast.isEmpty ? "还没有喂奶记录" : "上次喂奶 \(feedLast)"]
    if !sleepWoke.isEmpty { parts.append("\(sleepWoke) 醒") }
    return parts.joined(separator: " · ")
  }
}

/// 待处理动作队列 + 乐观更新
enum HHQueue {
  struct Item: Codable { let id: String; let a: String; let t: Double }

  static func items(_ d: UserDefaults = HH.defaults) -> [Item] {
    guard let s = d.string(forKey: HH.pendingKey), let data = s.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
  }

  /// action: "start:feed" / "end:sleep" / "diaper"（与安卓按钮 id 相同）
  static func perform(_ action: String, at now: Date = Date()) {
    let d = HH.defaults
    var list = items(d)
    list.append(Item(id: UUID().uuidString, a: action, t: now.timeIntervalSince1970 * 1000))
    if let data = try? JSONEncoder().encode(list), let s = String(data: data, encoding: .utf8) {
      d.set(s, forKey: HH.pendingKey)
    }
    // 乐观更新快照：App 下次打开时会用数据库的真实状态覆盖
    let parts = action.split(separator: ":").map(String.init)
    if action == "diaper" {
      d.set(HH.hm(now), forKey: "hh_diaper_last")
      d.set("已记下换尿布", forKey: "hh_done")
    } else if parts.count == 2, let k = CareKind(rawValue: parts[1]), k.isTimed {
      let key = "hh_\(k.rawValue)_start"
      let running = ((d.object(forKey: key) as? NSNumber)?.doubleValue ?? 0) > 0
      if parts[0] == "start", !running {
        d.set(Int64(now.timeIntervalSince1970 * 1000), forKey: key)
        d.set("", forKey: "hh_done")
      } else if parts[0] == "end", running {
        d.set(Int64(0), forKey: key)
        if k == .feed { d.set(HH.hm(now), forKey: "hh_feed_last") }
        if k == .sleep { d.set(HH.hm(now), forKey: "hh_sleep_woke") }
        d.set("已记下\(k.label)", forKey: "hh_done")
      }
    }
    HH.reloadAll()
  }

  static func toggle(_ k: CareKind) {
    if !k.isTimed { perform("diaper"); return }
    perform(HHSnapshot.load().starts[k] == nil ? "start:\(k.rawValue)" : "end:\(k.rawValue)")
  }
}

// MARK: - App Intents（iOS 17 交互式小组件）

@available(iOS 17.0, *)
struct CareActionIntent: AppIntent {
  static var title: LocalizedStringResource = "哄哄快捷记录"
  static var description = IntentDescription("开始/结束喂奶、睡觉、拍嗝，或记一次换尿布")
  static var isDiscoverable: Bool = false

  @Parameter(title: "动作") var action: String

  init() {}
  init(_ action: String) { self.action = action }

  func perform() async throws -> some IntentResult {
    HHQueue.perform(action)
    #if canImport(ActivityKit)
    if action.hasPrefix("end:"), let k = CareKind(rawValue: String(action.dropFirst(4))) {
      await HHLive.end(k)
    }
    #endif
    return .result()
  }
}

#if canImport(ActivityKit)
/// 实时活动（锁屏 / 灵动岛）：每个进行中的计时一条
@available(iOS 16.1, *)
struct CareActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var start: Date
    var label: String
  }
  var kind: String
  var baby: String
}

/// 实时活动上的"结束"按钮：在 App 进程里执行（LiveActivityIntent），App 没在前台也能结束
@available(iOS 17.0, *)
struct EndSessionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "结束计时"
  static var isDiscoverable: Bool = false
  @Parameter(title: "类型") var kind: String

  init() {}
  init(kind: String) { self.kind = kind }

  func perform() async throws -> some IntentResult {
    HHQueue.perform("end:\(kind)")
    if let k = CareKind(rawValue: kind) { await HHLive.end(k) }
    return .result()
  }
}

enum HHLive {
  static func end(_ k: CareKind) async {
    guard #available(iOS 16.2, *) else { return }
    for a in Activity<CareActivityAttributes>.activities where a.attributes.kind == k.rawValue {
      await a.end(nil, dismissalPolicy: .immediate)
    }
  }

  /// 让实时活动和进行中的计时一致：没有的开、多余的关
  static func sync(baby: String, sessions: [(CareKind, Date)]) async {
    guard #available(iOS 16.2, *) else { return }
    let want = Dictionary(uniqueKeysWithValues: sessions.map { ($0.0.rawValue, $0.1) })
    for a in Activity<CareActivityAttributes>.activities {
      if let start = want[a.attributes.kind] {
        let st = CareActivityAttributes.ContentState(start: start, label: CareKind(rawValue: a.attributes.kind)?.running ?? "")
        if a.content.state != st { await a.update(ActivityContent(state: st, staleDate: nil)) }
      } else {
        await a.end(nil, dismissalPolicy: .immediate)
      }
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let existing = Set(Activity<CareActivityAttributes>.activities.map { $0.attributes.kind })
    for (k, start) in sessions where !existing.contains(k.rawValue) {
      _ = try? Activity.request(
        attributes: CareActivityAttributes(kind: k.rawValue, baby: baby),
        content: ActivityContent(state: .init(start: start, label: k.running), staleDate: nil),
        pushType: nil)
    }
  }
}
#endif
