import SwiftUI
import Charts
import Core

/// ログ（§4）。上半分が釣行、下半分が分析。どちらも横スクロールのカードで 1 画面に収める。
struct LogView: View {
    @Environment(AppServices.self) private var services
    @State private var model = LogViewModel()
    @State private var detail: Core.Session?
    @State private var analysis: AnalysisKind?
    @State private var reportSession: Core.Session?
    @State private var deleting: Core.Session?

    enum AnalysisKind: String, Identifiable { case hour, tide, spot; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: DS.Spacing.s) {
                header.frame(height: geo.size.height * 0.07)
                latestReport.frame(height: geo.size.height * 0.08)
                sessionCards.frame(height: geo.size.height * 0.33)
                analysisCards.frame(height: geo.size.height * 0.32)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.l)
        }
        .onAppear { model.attach(services) }
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in model.refresh() }
        .sheet(item: $detail) { SessionDetailView(session: $0, spotName: model.spots[$0.spotID]?.name ?? "釣り場") }
        .sheet(item: $analysis) { AnalysisDetailView(kind: $0, sessions: model.allSessions, spots: model.spots) }
        .sheet(item: $reportSession) { s in
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text(s.report?.summary ?? "").font(DS.Font.number(20)).foregroundStyle(DS.Color.textPrimary)
                Text(s.report?.body ?? "").font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Spacer()
            }
            .padding(DS.Spacing.l).frame(maxWidth: .infinity, alignment: .leading).background(DS.Color.background)
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("この釣行を削除", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("削除", role: .destructive) { if let d = deleting { model.delete(d) }; deleting = nil }
            Button("キャンセル", role: .cancel) { deleting = nil }
        }
    }

    private var header: some View {
        HStack {
            Picker("期間", selection: $model.period) {
                ForEach(LogViewModel.Period.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Spacer()
            HStack(spacing: DS.Spacing.xs) {
                Text("\(model.sessionCount)").font(DS.Font.number(18)).foregroundStyle(DS.Color.textPrimary)
                Text("釣行").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                Text("\(model.catchCount)").font(DS.Font.number(18)).foregroundStyle(DS.Color.textPrimary)
                Text("尾").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private var latestReport: some View {
        Group {
            if let r = model.latestReport {
                Button { reportSession = r.session } label: {
                    HStack {
                        Text(r.summary).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.m)
                    .frame(maxHeight: .infinity)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
            }
        }
    }

    private var sessionCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.m) {
                ForEach(model.cards) { card in
                    SessionCardView(card: card, duration: model.durationText(card.session))
                        .frame(width: 180)
                        .onTapGesture { detail = card.session }
                        .onLongPressGesture { deleting = card.session }
                }
                if model.cards.isEmpty {
                    Text("釣行はまだありません").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).padding()
                }
            }
        }
    }

    private var analysisCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.m) {
                analysisCard(.hour, headline: model.byHour.max { $0.count < $1.count }.map { $0.count > 0 ? "\($0.hour)時" : "—" } ?? "—") {
                    Chart(model.byHour, id: \.hour) { h in
                        BarMark(x: .value("時", h.hour), y: .value("尾", h.count)).foregroundStyle(DS.Color.accent)
                    }
                    .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { v in AxisValueLabel().foregroundStyle(DS.Color.textTertiary) } }
                    .chartYAxis(.hidden)
                }
                analysisCard(.tide, headline: model.byTide.prefix(3).max { $0.count < $1.count }.map { $0.count > 0 ? $0.label : "—" } ?? "—") {
                    Chart(model.byTide, id: \.label) { t in
                        BarMark(x: .value("潮", t.label), y: .value("尾", t.count)).foregroundStyle(DS.Color.accent)
                    }
                    .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 8)).foregroundStyle(DS.Color.textTertiary) } }
                    .chartYAxis(.hidden)
                }
                analysisCard(.spot, headline: model.bySpot.first.map { String(format: "%.1f尾/h", $0.perHour) } ?? "—") {
                    Chart(model.bySpot.prefix(5), id: \.name) { s in
                        BarMark(x: .value("尾/h", s.perHour), y: .value("釣り場", s.name)).foregroundStyle(DS.Color.accent)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(DS.Color.textSecondary) } }
                }
            }
        }
    }

    private func analysisCard<C: View>(_ kind: AnalysisKind, headline: String, @ViewBuilder chart: () -> C) -> some View {
        Button { analysis = kind } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text(kind == .hour ? "時間帯" : (kind == .tide ? "潮" : "釣り場")).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                    Text(headline).font(DS.Font.number(16)).foregroundStyle(DS.Color.accent)
                }
                chart()
            }
            .padding(DS.Spacing.m)
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 釣行カード：ベストショットを背景に、日付・釣り場・尾数・滞在時間。ボウズは写真なしのグレー。
struct SessionCardView: View {
    let card: LogViewModel.SessionCard
    let duration: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = card.thumbnail, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.clear, DS.Color.background.opacity(0.85)], startPoint: .center, endPoint: .bottom))
            } else {
                DS.Color.surface
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.session.startedAt, format: .dateTime.month().day()).font(DS.Font.number(15)).foregroundStyle(DS.Color.textPrimary)
                Text(card.spotName).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                HStack(spacing: DS.Spacing.s) {
                    Text(card.session.isBlank ? "ボウズ" : "\(card.session.catches.count)尾").font(DS.Font.number(14))
                        .foregroundStyle(card.session.isBlank ? DS.Color.textTertiary : DS.Color.accent)
                    Text(duration).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .padding(DS.Spacing.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .opacity(card.session.isBlank ? 0.7 : 1)
    }
}
