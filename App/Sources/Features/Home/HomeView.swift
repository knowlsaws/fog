import SwiftUI
import Charts
import Core

/// ホーム（§3）。開いた瞬間に「今釣れるか」を数字で、「なぜか」を 4 チップで、「次に何が変わるか」をイベント列で示す。
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @State private var model = HomeViewModel()
    @State private var showBreakdown = false
    @State private var showSpots = false
    @State private var showSettings = false
    @State private var showMoon = false
    @State private var chipDetail: HomeViewModel.Chip?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header.frame(height: geo.size.height * 0.08)
                scoreArea.frame(height: geo.size.height * 0.20)
                chipsRow.frame(height: geo.size.height * 0.12)
                eventsRow.frame(height: geo.size.height * 0.065)
                ForecastChart(model: model).frame(height: geo.size.height * 0.52)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.s)
        }
        .onAppear { model.attach(services) }
        .task { await model.refresh() }
        .task {
            // 30 秒ごとに「今」を更新（釣れ率・チップ・次のイベント）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in Task { await model.refresh() } }
        .sheet(isPresented: $showBreakdown) { BreakdownSheet(result: model.score).presentationDetents([.medium]) }
        .sheet(isPresented: $showSpots) { SpotSwitchSheet(model: model) { showSpots = false }.presentationDetents([.large]) }
        .sheet(item: $chipDetail) { ChipDetailSheet(chip: $0, model: model).presentationDetents([.medium]) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showMoon) { MoonSheet(model: model).presentationDetents([.medium]) }
    }

    // MARK: ヘッダー

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.s) {
                    if model.isRecording { PulsingDot() }
                    Button { showSpots = true } label: {
                        HStack(spacing: 6) {
                            Text(model.spot?.name ?? "釣り場").font(.system(size: 24, weight: .bold)).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                            Image(systemName: "location.north.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Color.textSecondary).rotationEffect(.degrees(45))
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text(model.now, format: .dateTime.hour().minute()).font(DS.Font.number(14)).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
            Button { showMoon = true } label: {
                Image(systemName: MoonSymbol.name(age: model.moonAge)).font(.system(size: 20)).foregroundStyle(DS.Color.moon).frame(height: 32)
            }
            .buttonStyle(.plain)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(DS.Color.textSecondary).frame(height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, DS.Spacing.s)
    }

    // MARK: 釣れ率

    private var scoreArea: some View {
        Button { showBreakdown = true } label: {
            ZStack {
                // 円は常に画面中央（魚種別の数字があっても動かさない）
                ZStack {
                    // 下が開いた 270° のゲージ（確定画像）。トラックは暗いグレー
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Circle().trim(from: 0, to: 0.75 * CGFloat(model.score?.score ?? 0) / 100)
                        .stroke(model.score?.isForecast == true ? DS.Color.accent.opacity(0.6) : DS.Color.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .animation(.easeOut(duration: 0.6), value: model.score?.score)
                    Text("\(model.score?.score ?? 0)")
                        .font(DS.Font.score(76))
                        .foregroundStyle(DS.Color.textPrimary)
                        .contentTransition(.numericText())
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.vertical, DS.Spacing.s)
                if !model.speciesScores.isEmpty {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            ForEach(model.speciesScores, id: \.species) { s in
                                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                    Text("\(s.score)").font(DS.Font.number(22)).foregroundStyle(DS.Color.textPrimary)
                                    Text(s.species).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                                }
                            }
                        }
                        .frame(width: 100, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: 今（4 チップ）

    private var chipsRow: some View {
        HStack(spacing: DS.Spacing.s) {
            ForEach(model.chips) { chip in
                Button { chipDetail = chip } label: {
                    VStack(spacing: 3) {
                        Image(systemName: chip.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(iconColor(chip))
                            .rotationEffect(chip.kind == .wind ? .degrees((model.windDirectionDeg ?? 0) + 180) : .zero)
                            .frame(height: 22)
                        Text(chip.value).font(DS.Font.number(19)).foregroundStyle(DS.Color.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                        Text(chip.label).font(.system(size: 10, weight: .medium)).foregroundStyle(DS.Color.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, DS.Spacing.s)
                    .padding(.horizontal, DS.Spacing.xs)
                    .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// アイコンの色（確定画像：潮と光はオレンジ、風は緑、天気は白。悪い状態はグレー）
    private func iconColor(_ chip: HomeViewModel.Chip) -> Color {
        if chip.tone == .bad { return DS.Color.textTertiary }
        switch chip.kind {
        case .tide, .light: return DS.Color.accent
        case .wind: return DS.Color.secondary
        case .weather: return DS.Color.textPrimary
        }
    }

    // MARK: 次（イベント列）

    private var eventsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.events.prefix(3).enumerated()), id: \.element.at) { i, e in
                if i > 0 { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1).padding(.vertical, DS.Spacing.s) }
                Button { model.show(date: e.at) } label: {
                    VStack(spacing: 2) {
                        Text(e.label).font(DS.Font.caption).foregroundStyle(e.isPositive ? DS.Color.accent : DS.Color.textTertiary)
                        Text(e.at, format: .dateTime.hour().minute()).font(DS.Font.number(15)).foregroundStyle(e.isPositive ? DS.Color.accent : DS.Color.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
            if model.events.isEmpty {
                Text("—").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.vertical, DS.Spacing.xs)
    }
}

/// 記録中のオレンジの点（脈動）。
struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(DS.Color.accent).frame(width: 8, height: 8)
            .scaleEffect(on ? 1.3 : 0.8).opacity(on ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// 月の詳細（ヘッダーの月相アイコンをタップ）：月相名、月齢、輝面比、今日の月の出・月の入、次の満月・新月。
struct MoonSheet: View {
    let model: HomeViewModel

    var body: some View {
        let age = model.moonAge
        let times = MoonCalculator.times(on: model.now, at: model.coordinate, timeZone: model.timeZone)
        let fraction = MoonCalculator.illuminatedFraction(at: model.now)
        let synodic = 29.530589
        let toFull = ((14.765 - age) + synodic).truncatingRemainder(dividingBy: synodic)
        let toNew = (synodic - age).truncatingRemainder(dividingBy: synodic)
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: MoonSymbol.name(age: age)).font(.system(size: 40)).foregroundStyle(DS.Color.moon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MoonSymbol.phaseName(age: age)).font(DS.Font.number(24)).foregroundStyle(DS.Color.textPrimary)
                    Text(String(format: "月齢 %.1f · 輝面 %d%%", age, Int((fraction * 100).rounded()))).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
            }
            row("月の出", times.moonrise.map { $0.formatted(.dateTime.hour().minute()) } ?? "—")
            row("月の入", times.moonset.map { $0.formatted(.dateTime.hour().minute()) } ?? "—")
            row("次の満月", model.now.addingTimeInterval(toFull * 86_400).formatted(.dateTime.month().day()) + "（\(Int(toFull.rounded())) 日後）")
            row("次の新月", model.now.addingTimeInterval(toNew * 86_400).formatted(.dateTime.month().day()) + "（\(Int(toNew.rounded())) 日後）")
            if let moon = model.score?.breakdown.first(where: { $0.factor == .moon }) {
                row("釣れ率への影響", (moon.points > 0 ? "+" : "") + "\(Int(moon.points)) " + moon.detail)
            }
            Text("潮の大きさ（大潮・小潮）は月齢から決まります。月相の加点は満月・新月の前後で +2 です。")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.background)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
            Spacer()
            Text(value).font(DS.Font.number(16)).foregroundStyle(DS.Color.textPrimary)
        }
    }
}

enum MoonSymbol {
    /// 月齢から日本語の月相名
    static func phaseName(age: Double) -> String {
        switch age {
        case ..<1.8, 27.7...: return "新月"
        case ..<5.5: return "三日月"
        case ..<9.2: return "上弦"
        case ..<12.9: return "十三夜"
        case ..<16.6: return "満月"
        case ..<20.3: return "十六夜"
        case ..<24: return "下弦"
        default: return "有明"
        }
    }

    static func name(age: Double) -> String {
        switch age {
        case ..<1.8, 27.7...: return "moonphase.new.moon"
        case ..<5.5: return "moonphase.waxing.crescent"
        case ..<9.2: return "moonphase.first.quarter"
        case ..<12.9: return "moonphase.waxing.gibbous"
        case ..<16.6: return "moonphase.full.moon"
        case ..<20.3: return "moonphase.waning.gibbous"
        case ..<24: return "moonphase.last.quarter"
        default: return "moonphase.waning.crescent"
        }
    }
}

/// 先の推移：1 日ずつ表示し、左右スワイプ（または矢印）で日を送る。
/// 上：釣れ率（オレンジ、左軸 0〜100）と潮位（海の青、満干の時刻）。下：3 時間ごとの天気・気温・雨・風向・風速・波高の表。
struct ForecastChart: View {
    let model: HomeViewModel
    /// 潮位曲線を置く高さ（釣れ率の目盛りで 4〜40 の帯）
    private let tideBand: ClosedRange<Double> = 4...40
    private let hours = Array(stride(from: 0, to: 24, by: 3))

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: DS.Spacing.xs) {
                dayHeader.frame(height: 22)
                chart.frame(height: geo.size.height * 0.40)
                detailTable
                footer.frame(height: 16)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.s)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -30 { step(+1) } else if v.translation.width > 30 { step(-1) }
            })
        }
    }

    private func step(_ d: Int) {
        let next = model.dayOffset + d
        guard model.dayOffsetRange.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { model.dayOffset = next }
    }

    private var dayHeader: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(model.dayOffset > model.dayOffsetRange.lowerBound ? DS.Color.textSecondary : DS.Color.faded).frame(width: 28, height: 22) }
                .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                Text(model.dayStart, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated)).font(DS.Font.number(14)).foregroundStyle(DS.Color.textPrimary)
                Text(model.dayOffset == 0 ? "今日" : (model.dayOffset == 1 ? "明日" : (model.dayOffset == -1 ? "昨日" : ""))).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
            Button { step(+1) } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(model.dayOffset < model.dayOffsetRange.upperBound ? DS.Color.textSecondary : DS.Color.faded).frame(width: 28, height: 22) }
                .buttonStyle(.plain)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(dayShading, id: \.0) { (start, end) in
                RectangleMark(xStart: .value("s", start), xEnd: .value("e", end), yStart: .value("y0", 0), yEnd: .value("y1", 100))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
            ForEach(model.dayTide) { p in
                AreaMark(x: .value("時刻", p.at), yStart: .value("底", 0), yEnd: .value("潮位", tideY(p.levelCm)), series: .value("系列", "潮位面"))
                    .foregroundStyle(LinearGradient(colors: [DS.Color.sea.opacity(0.35), DS.Color.sea.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("時刻", p.at), y: .value("潮位", tideY(p.levelCm)), series: .value("系列", "潮位"))
                    .foregroundStyle(DS.Color.sea)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(model.dayExtremes, id: \.at) { e in
                PointMark(x: .value("時刻", e.at), y: .value("潮位", tideY(e.levelCm)))
                    .foregroundStyle(DS.Color.textPrimary)
                    .symbolSize(16)
                    .annotation(position: e.kind == .high ? .top : .bottom, spacing: 3) {
                        HStack(spacing: 2) {
                            Text(e.kind == .high ? "満" : "干").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            Text(e.at, format: .dateTime.hour().minute()).font(DS.Font.number(11)).foregroundStyle(DS.Color.textPrimary)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(DS.Color.background.opacity(0.85), in: Capsule())
                    }
            }
            ForEach(model.dayTimeline, id: \.at) { p in
                AreaMark(x: .value("時刻", p.at), yStart: .value("底", 0), yEnd: .value("釣れ率", p.score), series: .value("系列", "釣れ率面"))
                    .foregroundStyle(LinearGradient(colors: [DS.Color.accent.opacity(0.18), DS.Color.accent.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("時刻", p.at), y: .value("釣れ率", p.score), series: .value("系列", "釣れ率"))
                    .foregroundStyle(p.isForecast && model.forecastHorizon.map { p.at > $0 } == true ? DS.Color.accent.opacity(0.35) : DS.Color.accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            if model.now >= model.dayStart && model.now <= model.dayEnd {
                RuleMark(x: .value("今", model.now)).foregroundStyle(DS.Color.secondary).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: model.dayStart...model.dayEnd)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(DS.Color.faded.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)").font(DS.Font.number(9)).foregroundStyle(DS.Color.textTertiary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine().foregroundStyle(DS.Color.faded.opacity(0.3))
                if let d = value.as(Date.self) {
                    AxisValueLabel(centered: false) {
                        Text("\(Calendar.current.component(.hour, from: d))").font(DS.Font.number(9)).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
    }

    /// 3 時間ごとの詳細（天気・気温・雨・風向・風速・波高）
    private var detailTable: some View {
        let cols = model.dayDetail
        return VStack(spacing: 2) {
            tableRow("時刻") { i in Text("\(hours[i])").font(DS.Font.number(10)).foregroundStyle(DS.Color.textSecondary) }
            tableRow("天気") { i in
                Image(systemName: HomeViewModel.weatherSymbol(cols[i].conditionCode))
                    .font(.system(size: 12)).symbolRenderingMode(.multicolor)
                    .foregroundStyle(cols[i].conditionCode == nil ? DS.Color.faded : DS.Color.textPrimary)
            }
            tableRow("気温") { i in Text(cols[i].airTemperatureC.map { "\(Int($0.rounded()))°" } ?? "—").font(DS.Font.number(10)).foregroundStyle(DS.Color.textPrimary) }
            tableRow("雨") { i in Text(cols[i].precipitationMM.map { $0 < 0.05 ? "0" : String(format: "%.1f", $0) } ?? "—").font(DS.Font.number(10)).foregroundStyle((cols[i].precipitationMM ?? 0) > 0.5 ? DS.Color.sea : DS.Color.textSecondary) }
            tableRow("風向") { i in
                VStack(spacing: 0) {
                    Image(systemName: "location.north.fill").font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees((cols[i].windDirectionDeg ?? 0) + 180))
                        .foregroundStyle(cols[i].windDirectionDeg == nil ? DS.Color.faded : DS.Color.textPrimary)
                    Text(cols[i].windDirectionDeg.map { HomeViewModel.compass($0) } ?? "").font(.system(size: 8)).foregroundStyle(DS.Color.textTertiary)
                }
            }
            tableRow("風速") { i in Text(cols[i].windSpeedMS.map { String(format: "%.1f", $0) } ?? "—").font(DS.Font.number(10)).foregroundStyle((cols[i].windSpeedMS ?? 0) > 8 ? DS.Color.accent : DS.Color.textPrimary) }
            tableRow("波高") { i in Text(cols[i].waveHeightM.map { String(format: "%.1fm", $0) } ?? "—").font(DS.Font.number(10)).foregroundStyle(DS.Color.textPrimary) }
        }
    }

    private func tableRow<C: View>(_ label: String, @ViewBuilder cell: @escaping (Int) -> C) -> some View {
        HStack(spacing: 0) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).frame(width: 30, alignment: .leading)
            ForEach(0..<hours.count, id: \.self) { i in
                Group {
                    if i < model.dayDetail.count { cell(i) } else { Text("—").font(DS.Font.caption).foregroundStyle(DS.Color.faded) }
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium").font(.system(size: 10)).foregroundStyle(DS.Color.sea)
                Text(model.seaSurfaceTempC.map { String(format: "水温 %.1f°", $0) } ?? "水温 —").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            if let n = model.nextFetchAt {
                Text("次回更新 ").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) + Text(n, format: .dateTime.hour().minute()).font(DS.Font.number(10)).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    /// 潮位（cm）を釣れ率の目盛りの下帯に写す
    private func tideY(_ level: Double) -> Double {
        let lo = tideRange.lowerBound, hi = tideRange.upperBound
        let t = (level - lo) / (hi - lo)
        return tideBand.lowerBound + t * (tideBand.upperBound - tideBand.lowerBound)
    }

    private var tideRange: ClosedRange<Double> {
        let levels = model.tideCurve.map(\.levelCm)
        guard let lo = levels.min(), let hi = levels.max(), hi > lo else { return 0...200 }
        return lo...hi
    }

    /// 夜の区間（日の入〜翌日の出）。表示中の日に重なるものだけ
    private var dayShading: [(Date, Date)] {
        var out: [(Date, Date)] = []
        let days = model.sunTimesByDay
        for (i, d) in days.enumerated() {
            guard let sunset = d.sunset else { continue }
            let nextRise = i + 1 < days.count ? days[i + 1].sunrise : nil
            out.append((sunset, nextRise ?? sunset.addingTimeInterval(12 * 3600)))
        }
        if let first = days.first?.sunrise { out.append((model.rangeStart, first)) }
        return out.compactMap { (s, e) in
            let a = max(s, model.dayStart), b = min(e, model.dayEnd)
            return a < b ? (a, b) : nil
        }
    }
}

/// 内訳シート：どの要素が何点上げ下げしているか。
struct BreakdownSheet: View {
    let result: ScoreResult?
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("\(result?.score ?? 0)").font(DS.Font.score(48)).foregroundStyle(DS.Color.textPrimary)
                Text(result?.confidence == .forecast ? "予報" : (result?.confidence == .noWeather ? "気象なし" : "実況")).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                Spacer()
            }
            ForEach(Array((result?.breakdown ?? []).enumerated()), id: \.offset) { _, b in
                HStack {
                    Text(label(b.factor)).font(DS.Font.label).foregroundStyle(DS.Color.textSecondary).frame(width: 64, alignment: .leading)
                    Text(b.detail).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                    Text(b.points > 0 ? "+\(Int(b.points))" : "\(Int(b.points))")
                        .font(DS.Font.number(16))
                        .foregroundStyle(b.points > 0 ? DS.Color.accent : (b.points < 0 ? DS.Color.textTertiary : DS.Color.textSecondary))
                }
            }
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.background)
    }

    func label(_ f: ScoreBreakdown.Factor) -> String {
        switch f {
        case .light: return "光"
        case .tide: return "潮"
        case .pressure: return "気圧"
        case .wind: return "風"
        case .wave: return "波"
        case .water: return "水温"
        case .moon: return "月"
        case .personal: return "実績"
        }
    }
}

/// チップ詳細：その要素の数値と直近の推移。
struct ChipDetailSheet: View {
    let chip: HomeViewModel.Chip
    let model: HomeViewModel
    @Environment(AppServices.self) private var services
    @State private var refreshing = false

    var body: some View {
        let env = services.environment.snapshot(at: model.now, coordinate: model.coordinate)
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                Text(chip.value).font(DS.Font.number(28)).foregroundStyle(DS.Color.textPrimary)
                Text(chip.label).font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
            }
            switch chip.kind {
            case .tide:
                row("潮位", env.tideLevelCm.map { "\(Int($0.rounded())) cm" })
                row("変化率", env.tideRateCmPerHour.map { String(format: "%+.1f cm/h", $0) })
                row("次の満潮", env.nextHighTideAt.map { $0.formatted(.dateTime.hour().minute()) })
                row("次の干潮", env.nextLowTideAt.map { $0.formatted(.dateTime.hour().minute()) })
                row("月齢", env.moonAge.map { String(format: "%.1f", $0) })
            case .light:
                row("日の出", env.sunriseAt.map { $0.formatted(.dateTime.hour().minute()) })
                row("日の入", env.sunsetAt.map { $0.formatted(.dateTime.hour().minute()) })
            case .wind:
                row("風速", env.windSpeedMS.map { String(format: "%.1f m/s", $0) })
                row("最大瞬間", env.windGustMS.map { String(format: "%.1f m/s", $0) })
                row("風向", env.windDirectionDeg.map { "\(Int($0.rounded()))°" })
                row("波高", env.waveHeightM.map { String(format: "%.1f m", $0) })
                row("周期", env.wavePeriodS.map { String(format: "%.0f s", $0) })
            case .weather:
                row("気温", env.airTemperatureC.map { String(format: "%.1f℃", $0) })
                row("水温", env.seaSurfaceTempC.map { String(format: "%.1f℃", $0) })
                row("気圧", (env.measuredPressureHPa ?? env.pressureHPa).map { String(format: "%.1f hPa", $0) })
                row("気圧傾向", env.pressureTrend3hHPa.map { String(format: "%+.1f hPa/3h", $0) })
                row("湿度", env.humidity.map { "\(Int(($0 * 100).rounded()))%" })
                row("降水", env.precipitationMM.map { String(format: "%.1f mm", $0) })
            }
            if chip.kind == .wind || chip.kind == .weather {
                fetchStatus
            }
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.background)
    }

    /// 気象の取得状態：取得元、最後に取れた時刻、失敗の内容、再取得ボタン（実機での切り分け用）
    private var fetchStatus: some View {
        let env = services.environment
        let key = ForecastCache.key(for: model.coordinate)
        let last = env.cache.entry(for: model.coordinate)?.weatherFetchedAt
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Divider().overlay(DS.Color.faded)
            row("取得元", "Apple Weather（WeatherKit）")
            row("最後の取得", last.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "まだ取れていません")
            row("位置", String(format: "%.3f, %.3f", model.coordinate.latitude, model.coordinate.longitude))
            if let err = env.lastError {
                Text(err).font(DS.Font.caption).foregroundStyle(DS.Color.accent).fixedSize(horizontal: false, vertical: true)
            } else if last == nil, env.gate.lastFetch["weather:" + key] != nil {
                Text("取得中…").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Button {
                refreshing = true
                Task { await model.forceRefreshEnvironment(); refreshing = false }
            } label: {
                Text(refreshing ? "取得中…" : "いま再取得").font(DS.Font.label).foregroundStyle(DS.Color.background)
                    .padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s).background(DS.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(refreshing)
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
            Spacer()
            Text(value ?? "—").font(DS.Font.number(16)).foregroundStyle(DS.Color.textPrimary)
        }
    }
}

/// 釣り場切替：現在地、登録済みの釣り場、近い順の漁港（検索で全国）。漁港を選ぶと登録してホームの釣り場になる。
struct SpotSwitchSheet: View {
    let model: HomeViewModel
    let onDone: () -> Void
    @State private var query = ""

    var body: some View {
        let registered = model.availableSpots
        let ports = model.ports(matching: query)
        let origin = model.currentLocation
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("釣り場").font(.system(size: 22, weight: .bold)).foregroundStyle(DS.Color.textPrimary)
            TextField("漁港名で探す（全国）", text: $query)
                .font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                .padding(DS.Spacing.m).background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    if query.isEmpty {
                        rowButton(title: "現在地", subtitle: "今いる場所の情報を出す", selected: model.isUsingCurrentLocation, accent: true) {
                            model.selectCurrentLocation(); onDone()
                        }
                        if !registered.isEmpty {
                            Text("登録した釣り場").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).padding(.top, DS.Spacing.s)
                            ForEach(registered) { s in
                                rowButton(title: s.name, subtitle: origin.map { Self.distance($0, s.coordinate) } ?? "", selected: !model.isUsingCurrentLocation && s.id == model.spot?.id, accent: false) {
                                    model.select(spot: s); onDone()
                                }
                            }
                        }
                        Text("近くの漁港").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).padding(.top, DS.Spacing.s)
                    }
                    ForEach(ports.filter { p in !registered.contains { Geo.distanceMeters($0.coordinate, p.coordinate) < 300 } }) { p in
                        rowButton(title: p.name, subtitle: origin.map { Self.distance($0, p.coordinate) } ?? (p.pref ?? ""), selected: false, accent: false) {
                            model.select(port: p); onDone()
                        }
                    }
                    if ports.isEmpty {
                        Text("見つかりません").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
    }

    private func rowButton(title: String, subtitle: String, selected: Bool, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    if !subtitle.isEmpty { Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
                }
                Spacer()
                if selected { Circle().fill(DS.Color.accent).frame(width: 8, height: 8) }
                else if accent { Image(systemName: "location.fill").font(.system(size: 12)).foregroundStyle(DS.Color.textSecondary) }
            }
            .padding(DS.Spacing.m)
            .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private static func distance(_ a: Coordinate, _ b: Coordinate) -> String {
        let m = Geo.distanceMeters(a, b)
        return m < 1000 ? "\(Int(m)) m" : String(format: "%.1f km", m / 1000)
    }
}
