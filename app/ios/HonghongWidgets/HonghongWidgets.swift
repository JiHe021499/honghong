// 哄哄小组件扩展：桌面小组件（小/中）、锁屏小组件、实时活动、控制中心按钮（iOS 18）。
// 设计说明见 docs/design/ios-widgets.md。
import SwiftUI
import WidgetKit
import AppIntents
import ActivityKit

// MARK: - 时间线

struct HHEntry: TimelineEntry {
  let date: Date
  let snap: HHSnapshot
}

struct HHProvider: TimelineProvider {
  func placeholder(in context: Context) -> HHEntry {
    HHEntry(date: .now, snap: HHSnapshot(baby: "小米粒", starts: [:], feedLast: "15:00", sleepWoke: "16:20", diaperLast: "", done: ""))
  }
  func getSnapshot(in context: Context, completion: @escaping (HHEntry) -> Void) {
    completion(HHEntry(date: .now, snap: .load()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<HHEntry>) -> Void) {
    // 计时由 Text(timerInterval:) 自己走秒；App 每次数据变化都会主动刷新，这里每 30 分钟兜底一次
    completion(Timeline(entries: [HHEntry(date: .now, snap: .load())], policy: .after(.now.addingTimeInterval(1800))))
  }
}

// MARK: - 视觉

enum HHColor {
  static let cream = Color(red: 1.0, green: 0.973, blue: 0.941)
  static let peach = Color(red: 1.0, green: 0.596, blue: 0.455)
  static let peachL = Color(red: 1.0, green: 0.906, blue: 0.859)
  static let deep = Color(red: 0.878, green: 0.404, blue: 0.247)
  static let ink = Color(red: 0.239, green: 0.227, blue: 0.271)
  static let sub = Color(red: 0.541, green: 0.518, blue: 0.580)
  static let line = Color(red: 0.941, green: 0.902, blue: 0.863)
}

struct ActionButton: View {
  let kind: CareKind
  let running: Bool
  var compact = false

  var body: some View {
    let action = !kind.isTimed ? "diaper" : (running ? "end:\(kind.rawValue)" : "start:\(kind.rawValue)")
    let title = !kind.isTimed ? kind.label : (running ? "结束\(kind.label)" : (compact ? kind.label : "开始\(kind.label)"))
    Button(intent: CareActionIntent(action)) {
      VStack(spacing: 2) {
        if !compact { Image(kind.icon).resizable().scaledToFit().frame(width: 28, height: 28) }
        Text(title).font(.system(size: 11, weight: running ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, minHeight: compact ? 30 : 52)
      .foregroundStyle(running ? Color.white : HHColor.ink)
      .background(running ? HHColor.peach : Color.white, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(running ? HHColor.peach : HHColor.line, lineWidth: 1.5))
    }
    .buttonStyle(.plain)
  }
}

struct Header: View {
  let snap: HHSnapshot
  var body: some View {
    HStack(spacing: 8) {
      if let p = snap.primary {
        Image(p.kind.icon).resizable().scaledToFit().frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(p.kind.running).font(.system(size: 15, weight: .heavy)).foregroundStyle(HHColor.ink)
          Text(snap.subtitle).font(.system(size: 11)).foregroundStyle(HHColor.sub).lineLimit(1)
        }
        Spacer(minLength: 4)
        Text(timerInterval: p.start...Date.distantFuture, countsDown: false)
          .font(.system(size: 14, weight: .heavy).monospacedDigit())
          .foregroundStyle(HHColor.deep)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 70, alignment: .trailing)
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(HHColor.peachL, in: RoundedRectangle(cornerRadius: 10))
      } else {
        Image("avatar_baby").resizable().scaledToFit().frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(snap.baby).font(.system(size: 15, weight: .heavy)).foregroundStyle(HHColor.ink)
          Text(snap.done.isEmpty ? snap.subtitle : snap.done).font(.system(size: 11)).foregroundStyle(HHColor.sub).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

struct HomeWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: HHEntry

  var body: some View {
    let s = entry.snap
    VStack(alignment: .leading, spacing: 10) {
      Header(snap: s)
      Spacer(minLength: 0)
      if family == .systemSmall {
        // 小号：最主要的计时（或喂奶）+ 换尿布
        let main = s.primary?.kind ?? .feed
        HStack(spacing: 6) {
          ActionButton(kind: main, running: s.starts[main] != nil, compact: true)
          ActionButton(kind: .diaper, running: false, compact: true)
        }
      } else {
        HStack(spacing: 6) {
          ForEach([CareKind.feed, .sleep, .burp, .diaper], id: \.self) { k in
            ActionButton(kind: k, running: s.starts[k] != nil)
          }
        }
      }
    }
    .containerBackground(HHColor.cream, for: .widget)
    .widgetURL(URL(string: "honghong://home"))
  }
}

struct HHHomeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "HonghongHome", provider: HHProvider()) { HomeWidgetView(entry: $0) }
      .configurationDisplayName("哄哄 · 快捷记录")
      .description("开始/结束喂奶、睡觉、拍嗝，一点记换尿布")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - 锁屏小组件

struct LockWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: HHEntry

  var body: some View {
    let s = entry.snap
    Group {
      switch family {
      case .accessoryCircular:
        if let p = s.primary {
          VStack(spacing: 0) {
            Text(p.kind.label).font(.system(size: 10, weight: .bold))
            Text(timerInterval: p.start...Date.distantFuture, countsDown: false)
              .font(.system(size: 11, weight: .heavy).monospacedDigit()).multilineTextAlignment(.center)
          }
        } else {
          Button(intent: CareActionIntent("start:feed")) {
            VStack(spacing: 0) { Image(systemName: "plus.circle.fill").font(.title3); Text("喂奶").font(.system(size: 10)) }
          }.buttonStyle(.plain)
        }
      case .accessoryInline:
        if let p = s.primary {
          Text("\(p.kind.running) \(HH.hm(p.start)) 开始")
        } else {
          Text(s.feedLast.isEmpty ? "哄哄 · 还没有喂奶记录" : "上次喂奶 \(s.feedLast)")
        }
      default:
        VStack(alignment: .leading, spacing: 2) {
          if let p = s.primary {
            HStack {
              Text(p.kind.running).font(.headline)
              Text(timerInterval: p.start...Date.distantFuture, countsDown: false).font(.headline.monospacedDigit())
            }
            Button(intent: CareActionIntent("end:\(p.kind.rawValue)")) { Text("结束\(p.kind.label)").font(.caption.bold()) }
          } else {
            Text(s.baby).font(.headline)
            Text(s.subtitle).font(.caption).lineLimit(1)
            Button(intent: CareActionIntent("start:feed")) { Text("开始喂奶").font(.caption.bold()) }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .containerBackground(.clear, for: .widget)
    .widgetURL(URL(string: "honghong://home"))
  }
}

struct HHLockWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "HonghongLock", provider: HHProvider()) { LockWidgetView(entry: $0) }
      .configurationDisplayName("哄哄 · 锁屏")
      .description("锁屏上看计时、一点开始/结束")
      .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
  }
}

// MARK: - 实时活动（锁屏 + 灵动岛）

struct HHLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CareActivityAttributes.self) { ctx in
      let k = CareKind(rawValue: ctx.attributes.kind) ?? .feed
      HStack(spacing: 12) {
        Image(k.icon).resizable().scaledToFit().frame(width: 40, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(ctx.attributes.baby) · \(ctx.state.label)").font(.system(size: 15, weight: .bold)).foregroundStyle(HHColor.ink)
          Text("\(HH.hm(ctx.state.start)) 开始").font(.system(size: 12)).foregroundStyle(HHColor.sub)
        }
        Spacer()
        Text(timerInterval: ctx.state.start...Date.distantFuture, countsDown: false)
          .font(.system(size: 22, weight: .heavy).monospacedDigit()).foregroundStyle(HHColor.deep)
          .multilineTextAlignment(.trailing).frame(maxWidth: 96)
        Button(intent: EndSessionIntent(kind: k.rawValue)) {
          Text("结束").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(HHColor.peach, in: Capsule())
        }.buttonStyle(.plain)
      }
      .padding(14)
      .activityBackgroundTint(HHColor.cream)
    } dynamicIsland: { ctx in
      let k = CareKind(rawValue: ctx.attributes.kind) ?? .feed
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(k.icon).resizable().scaledToFit().frame(width: 36, height: 36)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(ctx.state.label).font(.headline)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(timerInterval: ctx.state.start...Date.distantFuture, countsDown: false)
            .font(.title3.monospacedDigit()).frame(maxWidth: 80)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Button(intent: EndSessionIntent(kind: k.rawValue)) {
            Text("结束\(k.label)").font(.subheadline.bold()).frame(maxWidth: .infinity)
          }.tint(HHColor.peach)
        }
      } compactLeading: {
        Image(k.icon).resizable().scaledToFit().frame(width: 22, height: 22)
      } compactTrailing: {
        Text(timerInterval: ctx.state.start...Date.distantFuture, countsDown: false)
          .monospacedDigit().frame(maxWidth: 52)
      } minimal: {
        Image(k.icon).resizable().scaledToFit().frame(width: 20, height: 20)
      }
      .widgetURL(URL(string: "honghong://home"))
    }
  }
}

// MARK: - 控制中心（iOS 18）：对应安卓下拉快捷开关

@available(iOS 18.0, *)
struct CareToggleIntent: SetValueIntent {
  static var title: LocalizedStringResource = "哄哄计时开关"
  static var isDiscoverable: Bool = false
  @Parameter(title: "类型") var kind: String
  @Parameter(title: "开") var value: Bool

  init() {}
  init(kind: String) { self.kind = kind }

  func perform() async throws -> some IntentResult {
    guard let k = CareKind(rawValue: kind) else { return .result() }
    let running = HHSnapshot.load().starts[k] != nil
    if value != running { HHQueue.perform(value ? "start:\(kind)" : "end:\(kind)") }
    return .result()
  }
}

@available(iOS 18.0, *)
struct CareControlValue: ControlValueProvider {
  let kind: CareKind
  var previewValue: Bool { false }
  func currentValue() async throws -> Bool { HHSnapshot.load().starts[kind] != nil }
}

@available(iOS 18.0, *)
struct FeedControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "HonghongControlFeed", provider: CareControlValue(kind: .feed)) { on in
      ControlWidgetToggle("喂奶", isOn: on, action: CareToggleIntent(kind: "feed")) { on in
        Label(on ? "喂奶中" : "喂奶", systemImage: on ? "waterbottle.fill" : "waterbottle")
      }
      .tint(HHColor.peach)
    }
    .displayName("哄哄 · 喂奶")
  }
}

@available(iOS 18.0, *)
struct SleepControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "HonghongControlSleep", provider: CareControlValue(kind: .sleep)) { on in
      ControlWidgetToggle("睡觉", isOn: on, action: CareToggleIntent(kind: "sleep")) { on in
        Label(on ? "睡觉中" : "睡觉", systemImage: on ? "moon.zzz.fill" : "moon.zzz")
      }
      .tint(HHColor.peach)
    }
    .displayName("哄哄 · 睡觉")
  }
}

@available(iOS 18.0, *)
struct DiaperControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "HonghongControlDiaper") {
      ControlWidgetButton(action: CareActionIntent("diaper")) {
        Label("换尿布", systemImage: "checkmark.circle")
      }
    }
    .displayName("哄哄 · 换尿布")
  }
}

// MARK: - 入口

@main
struct HonghongWidgets: WidgetBundle {
  var body: some Widget {
    HHHomeWidget()
    HHLockWidget()
    HHLiveActivity()
    if #available(iOS 18.0, *) {
      FeedControl()
      SleepControl()
      DiaperControl()
    }
  }
}
