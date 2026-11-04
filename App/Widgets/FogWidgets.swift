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

// MARK: - 部品（docs/ui/widgets.jpg を再現する）

/// 太いオレンジの円弧。未達の部分は暗いオレンジ。中央に大きな数字だけ。
private struct ScoreRing: View {
    let score: Int
    let size: CGFloat
    var lineWidth: CGFloat { size * 0.13 }
    var body: some View {
        ZStack {
            Circle().stroke(WColor.accent.opacity(0.28), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(WColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}

/// 潮グラフ：緑の曲線と薄い面、中央に細い横線。現在は細いオレンジの縦線。
private struct TideGraph: View {
    let points: [WidgetSnapshot.Point]
    let range: ClosedRange<Double>?
    let now: Date
    /// 潮位は海の青（ホームと同じ）
    private let green = Color(red: 0.30, green: 0.62, blue: 0.95)

    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: CGPoint(x: 0, y: geo.size.height / 2)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2)) }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
            if points.count >= 2, range != nil {
                areaPath(in: geo.size)
                    .fill(LinearGradient(colors: [green.opacity(0.35), green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                linePath(in: geo.size)
                    .stroke(green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                nowPath(in: geo.size)
                    .stroke(WColor.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }

    private func x(_ d: Date, width: CGFloat) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        let t0 = first.at.timeIntervalSince1970
        let span = max(1, last.at.timeIntervalSince1970 - t0)
        return CGFloat((d.timeIntervalSince1970 - t0) / span) * width
    }

    private func y(_ level: Double, height: CGFloat) -> CGFloat {
        guard let range else { return height / 2 }
        let lo = range.lowerBound, hi = range.upperBound
        let inset = height * 0.12
        return height - inset - CGFloat((level - lo) / (hi - lo)) * (height - inset * 2)
    }

    private func samples(in size: CGSize) -> [CGPoint] {
        let fallback = points.compactMap(\.tideLevelCm).first ?? (range?.lowerBound ?? 0)
        return points.map { CGPoint(x: x($0.at, width: size.width), y: y($0.tideLevelCm ?? fallback, height: size.height)) }
    }

    /// 点列を滑らかな曲線にする（Catmull-Rom → ベジェ）
    private func curve(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i], p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func linePath(in size: CGSize) -> Path { curve(samples(in: size)) }

    private func areaPath(in size: CGSize) -> Path {
        let pts = samples(in: size)
        var path = curve(pts)
        guard let last = pts.last, let first = pts.first else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func nowPath(in size: CGSize) -> Path {
        var path = Path()
        let nx = x(now, width: size.width)
        path.move(to: CGPoint(x: nx, y: 0))
        path.addLine(to: CGPoint(x: nx, y: size.height))
        return path
    }
}

/// 釣り竿のアイコン（SF Symbols に無いので描く）：斜めの竿、リール、先端から垂れる糸と針。
private struct RodIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.18, y: h * 0.88))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.12))
            }
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: max(1.5, w * 0.07), lineCap: .round))
            Circle().stroke(Color.white.opacity(0.9), lineWidth: max(1.2, w * 0.05))
                .frame(width: w * 0.2, height: w * 0.2)
                .position(x: w * 0.4, y: h * 0.62)
            Path { p in
                p.move(to: CGPoint(x: w * 0.78, y: h * 0.12))
                p.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.62), control: CGPoint(x: w * 0.92, y: h * 0.3))
                p.addArc(center: CGPoint(x: w * 0.8, y: h * 0.62), radius: w * 0.06, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            }
            .stroke(WColor.accent, style: StrokeStyle(lineWidth: max(1.2, w * 0.05), lineCap: .round))
        }
    }
}

/// 針のアイコン：上に小さな環、下が J 字。
private struct HookIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.62, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.62))
                p.addArc(center: CGPoint(x: w * 0.46, y: h * 0.62), radius: w * 0.16, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.5))
            }
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: max(1.5, w * 0.07), lineCap: .round, lineJoin: .round))
            Circle().stroke(Color.white.opacity(0.9), lineWidth: max(1.2, w * 0.05))
                .frame(width: w * 0.14, height: w * 0.14)
                .position(x: w * 0.62, y: h * 0.14)
            Path { p in
                p.move(to: CGPoint(x: w * 0.30, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.42))
            }
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: max(1.2, w * 0.05), lineCap: .round))
        }
    }
}

/// 丸ボタン：暗い円。撮影はグレーの縁、タックルと針ロストはオレジの細い縁。
private struct RoundAction<Content: View>: View {
    let accent: Bool
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.16, green: 0.16, blue: 0.17))
            Circle().stroke(accent ? WColor.accent : Color.white.opacity(0.22), lineWidth: accent ? 1.5 : 1)
            content
        }
        .frame(width: 54, height: 54)
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

// MARK: - ホーム画面・小：円弧と数字だけ

struct SmallScoreView: View {
    let entry: ScoreEntry
    var body: some View {
        GeometryReader { geo in
            ScoreRing(score: entry.score, size: min(geo.size.width, geo.size.height) * 0.78)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(entry.hasData ? 1 : 0.5)
        .fogWidgetBackground(recording: entry.isRecording)
        .widgetURL(URL(string: "fog://home"))
    }
}

// MARK: - ホーム画面・中：上に数字と潮グラフのパネル、下に 3 つの丸ボタン

struct MediumScoreView: View {
    let entry: ScoreEntry
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Text("\(entry.score)")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 70, alignment: .leading)
                TideGraph(points: entry.tide, range: entry.tideRange, now: entry.date)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Spacer(minLength: 0)
                Link(destination: URL(string: "fog://capture")!) {
                    RoundAction(accent: false) {
                        Image(systemName: "camera.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
                Button(intent: ToggleTackleIntent()) {
                    RoundAction(accent: true) {
                        RodIcon().frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button(intent: HookLostIntent()) {
                    RoundAction(accent: true) {
                        HookIcon().frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .fogWidgetBackground(recording: entry.isRecording)
        .widgetURL(URL(string: "fog://home"))
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

// MARK: - ロック画面：数字とオレンジのバー

struct LockScoreView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScoreEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.25), lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(max(0, min(100, entry.score))) / 100)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.score)").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .padding(2)
            case .accessoryInline:
                Text("釣れ率 \(entry.score)")
            default:
                HStack(spacing: 10) {
                    Text("\(entry.score)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.3))
                            Capsule().fill(Color.primary)
                                .frame(width: geo.size.width * CGFloat(max(0, min(100, entry.score))) / 100)
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, 2)
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
            .description("釣れ率とバー。タップで撮影")
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
