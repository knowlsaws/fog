import SwiftUI
import Core

/// 釣果情報（F-27）：登録 RSS から集めた記事の一覧。自分の魚種・釣り場に関係するものを先に、同じ強さなら新しい順。
/// 記事はタップでブラウザへ。縦スクロールを許す（図鑑グリッドと同じ例外）。
struct FeedView: View {
    let keywords: [String]
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = false
    @State private var onlyRelevant = false

    private var items: [FeedItem] {
        let all = services.feeds.sorted(keywords: keywords)
        return onlyRelevant ? all.filter { !FeedRelevance.matches($0, keywords: keywords).isEmpty } : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("釣果情報").font(DS.Font.number(20)).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button { onlyRelevant.toggle() } label: {
                    Text(onlyRelevant ? "関連だけ" : "全部").font(DS.Font.caption).foregroundStyle(onlyRelevant ? DS.Color.background : DS.Color.textPrimary)
                        .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.xs)
                        .background(onlyRelevant ? DS.Color.accent : DS.Color.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    refreshing = true
                    Task { await services.feeds.refreshIfNeeded(force: true); refreshing = false }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.Color.textSecondary).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(refreshing)
            }
            if services.feeds.urls.isEmpty {
                Text("設定 > 情報源 で釣りメディアや釣具店ブログの RSS を登録すると、ここに集まります").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else if items.isEmpty {
                Text(refreshing ? "取得中" : (services.feeds.lastError ?? "記事はまだありません")).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.s) {
                    ForEach(items) { item in row(item) }
                }
            }
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
    }

    private func row(_ item: FeedItem) -> some View {
        let hits = FeedRelevance.matches(item, keywords: keywords)
        let content = VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(2)
            if let s = item.summary, !s.isEmpty {
                Text(s).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(2)
            }
            HStack(spacing: DS.Spacing.s) {
                Text(item.feedTitle).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                if let d = item.publishedAt { Text(d, format: .dateTime.month().day().hour().minute()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
                Spacer()
                ForEach(hits.prefix(3), id: \.self) { k in
                    Text(k).font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Color.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(DS.Color.accent.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        return Group {
            if let link = item.link, let url = URL(string: link) { Link(destination: url) { content } } else { content }
        }
    }
}
