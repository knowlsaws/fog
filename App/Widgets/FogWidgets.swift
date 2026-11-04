import WidgetKit
import SwiftUI

/// プレースホルダー（L0）。L14 で実装。
struct ScoreEntry: TimelineEntry {
    let date: Date
    let score: Int
}

struct ScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoreEntry { ScoreEntry(date: .now, score: 72) }
    func getSnapshot(in context: Context, completion: @escaping (ScoreEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoreEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [placeholder(in: context)], policy: .after(next)))
    }
}

struct ScoreWidgetView: View {
    let entry: ScoreEntry
    var body: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.25), lineWidth: 8)
            Circle().trim(from: 0, to: CGFloat(entry.score) / 100)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(entry.score)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(12)
        .containerBackground(Color(red: 0.043, green: 0.043, blue: 0.047), for: .widget)
    }
}

@main
struct FogWidgets: WidgetBundle {
    var body: some Widget { ScoreWidget() }
}

struct ScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScoreWidget", provider: ScoreProvider()) { ScoreWidgetView(entry: $0) }
            .configurationDisplayName("釣れ率")
            .description("今の釣れ率")
            .supportedFamilies([.systemSmall])
    }
}
