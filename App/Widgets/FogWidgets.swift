import WidgetKit
import SwiftUI
import AppIntents
import Core

// MARK: - 色（ウィジェット拡張は App/Sources の DS を含まないので最小限をここに持つ）

private enum WColor {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.047)
    static let accent = Color(red: 1.0, green: 0.478, blue: 0.102)
    static let secondary = Color(red: 0.45, green: 0.62, blue: 0.47)
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.4)
}

// MARK: - エントリとプロバイダ

struct ScoreEntry: TimelineEntry {
    let date: Date
    let score: Int
    let tideRising: Bool?
    let nextEvent: WidgetSnapshot.Event?
    let isRecording: Bool
    let tackle: TackleKind?
    let spotName: String
    /// 中ウィジェットの潮グラフ（前後 6 時間）
    let tide: [WidgetSnapshot.Point]
    let tideRange: ClosedRange<Double>?
    let hasData: Bool

    static func sample(_ date: Date = .now) -> ScoreEntry {
        let pts = (0..<48).map { i in WidgetSnapshot.Point(at: date.addingTimeInterval(Double(i - 24) * 900), score: 72, tideRising: true, tideLevelCm: 100 + 60 * sin(Double(i) / 48 * .pi * 2)) }
        return ScoreEntry(date: date, score: 72, tideRising: true, nextEvent: WidgetSnapshot.Event(at: date.addingTimeInterval(80 * 60), label: "満潮"),
                          isRecording: false, tackle: .spinning, spotName: "函館港", tide: pts, tideRange: 40...160, hasData: true)
    }

    static func empty(_ date: Date = .now) -> ScoreEntry {
        ScoreEntry(date: date, score: 0, tideRising: nil, nextEvent: nil, isRecording: false, tackle: nil, spotName: "", tide: [], tideRange: nil, hasData: false)
    }

    static func make(at date: Date, from s: WidgetSnapshot) -> ScoreEntry {
        let p = s.point(at: date)
        let window = date.addingTimeInterval(-6 * 3600)...date.addingTimeInterval(6 * 3600)
        let tide = s.points.filter { window.contains($0.at) && $0.tideLevelCm != nil }
        return ScoreEntry(date: date, score: p?.score ?? 0, tideRising: p?.tideRising, nextEvent: s.nextEvent(after: date),
                          isRecording: s.isRecording, tackle: s.tackle ?? FogShared.currentTackle, spotName: s.spotName,
                          tide: tide, tideRange: s.tideRange(from: window.lowerBound, to: window.upperBound), hasData: p != nil)
    }
}

struct ScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreEntry { .sample() }

    func getSnapshot(in context: Context, completion: @escaping (ScoreEntry) -> Void) {
        if context.isPreview { completion(.sample()); return }
        completion(entries(now: .now).first ?? .empty())
    }

    /// 15 分ごとのエントリ（最長 24 時間）。スナップショットが切れたらアプリ側の再書き出しを待つ。
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreEntry>) -> Void) {
        let now = Date()
        let list = entries(now: now)
        let refresh = (list.last?.date ?? now).addingTimeInterval(15 * 60)
        completion(Timeline(entries: list, policy: .after(max(refresh, now.addingTimeInterval(15 * 60)))))
    }

    private func entries(now: Date) -> [ScoreEntry] {
        guard let s = FogShared.loadSnapshot() else { return [.empty(now)] }
        var points = s.timeline(from: now, stepMinutes: 15, count: 96)
        if points.isEmpty { points = [WidgetSnapshot.Point(at: now, score: s.point(at: now)?.score ?? 0)] }
        return points.map { ScoreEntry.make(at: $0.at, from: s) }
    }
}

// MARK: - 部品

private struct ScoreArc: View {
    let score: Int
    let size: CGFloat
    let lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(WColor.accent.opacity(0.2), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(WColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}

private struct TideArrow: View {
    let rising: Bool?
    var body: some View {
        Image(systemName: rising == nil ? "minus" : (rising! ? "arrow.up" : "arrow.down"))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(rising == nil ? WColor.textTertiary : WColor.secondary)
    }
}

private struct TideGraph: View {
    let points: [WidgetSnapshot.Point]
    let range: ClosedRange<Double>?
    let now: Date
    var body: some View {
        GeometryReader { geo in
            if points.count >= 2, let range {
                let t0 = points.first!.at.timeIntervalSince1970, t1 = points.last!.at.timeIntervalSince1970
                let span = max(1, t1 - t0)
                let levels = points.compactMap(\.tideLevelCm)
                let lo = range.lowerBound, hi = range.upperBound
                func x(_ d: Date) -> CGFloat { CGFloat((d.timeIntervalSince1970 - t0) / span) * geo.size.width }
                func y(_ l: Double) -> CGFloat { geo.size.height - CGFloat((l - lo) / (hi - lo)) * geo.size.height }
                Path { path in
                    for (i, p) in points.enumerated() {
                        let pt = CGPoint(x: x(p.at), y: y(p.tideLevelCm ?? levels.first ?? lo))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(WColor.textSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                let nx = x(now)
                Path { p in p.move(to: CGPoint(x: nx, y: 0)); p.addLine(to: CGPoint(x: nx, y: geo.size.height)) }
                    .stroke(WColor.accent, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                Text("—").font(.system(size: 11)).foregroundStyle(WColor.textTertiary)
            }
        }
    }
}

private extension View {
    /// 背景 #0B0B0C。記録中は薄いオレンジ（§8）。
    func fogWidgetBackground(recording: Bool) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                WColor.background
                if recording { WColor.accent.opacity(0.14) }
            }
        }
    }
}

// MARK: - ホーム画面・小

struct SmallScoreView: View {
    let entry: ScoreEntry
    var body: some View {
        VStack(spacing: 4) {
            ScoreArc(score: entry.score, size: 84, lineWidth: 8)
            HStack(spacing: 4) {
                TideArrow(rising: entry.tideRising)
                if let e = entry.nextEvent {
                    Text(e.label).font(.system(size: 11, weight: .medium)).foregroundStyle(WColor.textSecondary)
                    Text(e.at, style: .time).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(WColor.textSecondary)
                }
            }
        }
        .opacity(entry.hasData ? 1 : 0.4)
        .fogWidgetBackground(recording: entry.isRecording)
        .widgetURL(URL(string: "fog://home"))
    }
}

// MARK: - ホーム画面・中

struct MediumScoreView: View {
    let entry: ScoreEntry
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ScoreArc(score: entry.score, size: 76, lineWidth: 7)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        TideArrow(rising: entry.tideRising)
                        Text(entry.spotName.isEmpty ? "釣れ率" : entry.spotName).font(.system(size: 11, weight: .medium)).foregroundStyle(WColor.textTertiary).lineLimit(1)
                    }
                    TideGraph(points: entry.tide, range: entry.tideRange, now: entry.date).frame(height: 34)
                    if let e = entry.nextEvent {
                        HStack(spacing: 4) {
                            Text(e.label).font(.system(size: 12, weight: .medium)).foregroundStyle(WColor.textSecondary)
                            Text(e.at, style: .time).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Link(destination: URL(string: "fog://capture")!) {
                    actionLabel(system: "camera.fill", text: "撮影", filled: true)
                }
                Button(intent: ToggleTackleIntent()) {
                    actionLabel(system: "arrow.left.arrow.right", text: entry.tackle == .bait ? "ベイト" : "スピニング", filled: false)
                }
                .buttonStyle(.plain)
                Button(intent: HookLostIntent()) {
                    actionLabel(system: "xmark.circle", text: "針ロスト", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .fogWidgetBackground(recording: entry.isRecording)
        .widgetURL(URL(string: "fog://home"))
    }

    private func actionLabel(system: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(filled ? .white : WColor.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(filled ? WColor.accent : Color.white.opacity(0.08), in: Capsule())
    }
}

struct ScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScoreEntry
    var body: some View {
        switch family {
        case .systemMedium: MediumScoreView(entry: entry)
        default: SmallScoreView(entry: entry)
        }
    }
}

struct ScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScoreWidget", provider: ScoreProvider()) { ScoreWidgetView(entry: $0) }
            .configurationDisplayName("釣れ率")
            .description("今の釣れ率と潮。中サイズは撮影・タックル切替・針ロスト")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

// MARK: - ロック画面

struct LockScoreView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScoreEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(max(0, min(100, entry.score))), in: 0...100) {
                    Image(systemName: "fish")
                } currentValueLabel: {
                    Text("\(entry.score)").font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                if let e = entry.nextEvent {
                    Text("釣れ率 \(entry.score) · \(e.label) ") + Text(e.at, style: .time)
                } else {
                    Text("釣れ率 \(entry.score)")
                }
            default:
                HStack(spacing: 10) {
                    Text("\(entry.score)").font(.system(size: 34, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.spotName.isEmpty ? "釣れ率" : entry.spotName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if let e = entry.nextEvent {
                            Text("\(e.label)まで").font(.system(size: 11)).opacity(0.7)
                            Text(e.at, style: .timer).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        } else {
                            Text("—").opacity(0.5)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "fog://capture"))
    }
}

struct LockScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScoreWidget", provider: ScoreProvider()) { LockScoreView(entry: $0) }
            .configurationDisplayName("釣れ率（ロック画面）")
            .description("釣れ率と次のイベントまでの時間。タップで撮影")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct FogWidgets: WidgetBundle {
    var body: some Widget {
        ScoreWidget()
        LockScoreWidget()
    }
}
