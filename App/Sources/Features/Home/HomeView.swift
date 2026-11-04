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
    @State private var chipDetail: HomeViewModel.Chip?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header.frame(height: geo.size.height * 0.07)
                scoreArea.frame(height: geo.size.height * 0.22)
                chipsRow.frame(height: geo.size.height * 0.12)
                eventsRow.frame(height: geo.size.height * 0.07)
                ForecastChart(model: model).frame(height: geo.size.height * 0.40)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.l)
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
        .sheet(isPresented: $showSpots) { SpotSwitchSheet(spots: model.availableSpots, current: model.spot) { model.select(spot: $0); showSpots = false }.presentationDetents([.medium]) }
        .sheet(item: $chipDetail) { ChipDetailSheet(chip: $0, model: model).presentationDetents([.medium]) }
        .sheet(isPresented: $showSettings) { SettingsView() }
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
            Image(systemName: MoonSymbol.name(age: model.moonAge)).font(.system(size: 20)).foregroundStyle(DS.Color.moon).frame(height: 32)
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
                Button { model.scrollTarget = e.at } label: {
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

enum MoonSymbol {
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

/// 1 枚のグラフ：釣れ率のライン（オレンジ、左軸 0〜100）と、その下に潮位の曲線（グレー、満干の時刻付き）。
/// 時間軸は共有、現在はオレンジの縦線、夜は背景を暗く、予報の無い先は線を薄く。横スクロールとピンチで伸縮。
struct ForecastChart: View {
    let model: HomeViewModel
    @State private var visibleHours: Double = 24
    @State private var scrollPosition: Date = .now

    /// 潮位曲線を置く高さ（釣れ率の目盛りで 4〜40 の帯）
    private let tideBand: ClosedRange<Double> = 4...40

    var body: some View {
        Chart {
            ForEach(dayShading, id: \.0) { (start, end) in
                RectangleMark(xStart: .value("s", start), xEnd: .value("e", end), yStart: .value("y0", 0), yEnd: .value("y1", 100))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
            ForEach(model.tideCurve) { p in
                AreaMark(x: .value("時刻", p.at), yStart: .value("底", 0), yEnd: .value("潮位", tideY(p.levelCm)), series: .value("系列", "潮位面"))
                    .foregroundStyle(LinearGradient(colors: [DS.Color.sea.opacity(0.35), DS.Color.sea.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("時刻", p.at), y: .value("潮位", tideY(p.levelCm)), series: .value("系列", "潮位"))
                    .foregroundStyle(DS.Color.sea)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(model.tideExtremes, id: \.at) { e in
                PointMark(x: .value("時刻", e.at), y: .value("潮位", tideY(e.levelCm)))
                    .foregroundStyle(DS.Color.textPrimary)
                    .symbolSize(16)
                    .annotation(position: e.kind == .high ? .top : .bottom, spacing: 3) {
                        // 線と重なっても読めるよう、暗い小さな面に乗せる
                        HStack(spacing: 2) {
                            Text(e.kind == .high ? "満" : "干").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            Text(e.at, format: .dateTime.hour().minute()).font(DS.Font.number(11)).foregroundStyle(DS.Color.textPrimary)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(DS.Color.background.opacity(0.85), in: Capsule())
                    }
            }
            ForEach(model.timeline, id: \.at) { p in
                AreaMark(x: .value("時刻", p.at), yStart: .value("底", 0), yEnd: .value("釣れ率", p.score), series: .value("系列", "釣れ率面"))
                    .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("時刻", p.at), y: .value("釣れ率", p.score), series: .value("系列", "釣れ率"))
                    .foregroundStyle(p.isForecast && model.forecastHorizon.map { p.at > $0 } == true ? Color.white.opacity(0.35) : Color.white.opacity(0.92))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            RuleMark(x: .value("今", model.now)).foregroundStyle(DS.Color.secondary).lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(DS.Color.faded.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)").font(DS.Font.number(10)).foregroundStyle(DS.Color.textTertiary) }
                }
            }
        }
        .chartXAxis {
            // 6 時間ごとに時刻、0 時には月日（横スクロールしてもいつの情報か分かるように）
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                if let d = value.as(Date.self) {
                    let hour = Calendar.current.component(.hour, from: d)
                    AxisGridLine().foregroundStyle(hour == 0 ? DS.Color.faded : DS.Color.faded.opacity(0.4))
                    AxisValueLabel(centered: false) {
                        if hour == 0 {
                            Text(d, format: .dateTime.month(.defaultDigits).day()).font(DS.Font.number(10)).foregroundStyle(DS.Color.textSecondary)
                        } else {
                            Text("\(hour)").font(DS.Font.number(10)).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleHours * 3600)
        .chartScrollPosition(x: $scrollPosition)
        .padding(DS.Spacing.m)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .gesture(MagnifyGesture().onChanged { value in
            visibleHours = min(24 * 7, max(6, 24 / value.magnification))
        })
        .onAppear { scrollPosition = model.now.addingTimeInterval(-6 * 3600) }
        .onChange(of: model.scrollTarget) { _, target in
            if let target { withAnimation { scrollPosition = target.addingTimeInterval(-visibleHours * 3600 / 2) } }
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

    /// 夜の区間（日の入〜翌日の出）
    private var dayShading: [(Date, Date)] {
        var out: [(Date, Date)] = []
        let days = model.sunTimesByDay
        for (i, d) in days.enumerated() {
            guard let sunset = d.sunset else { continue }
            let nextRise = i + 1 < days.count ? days[i + 1].sunrise : nil
            out.append((sunset, nextRise ?? sunset.addingTimeInterval(12 * 3600)))
        }
        if let first = days.first?.sunrise { out.append((model.rangeStart, first)) }
        return out
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

/// 釣り場切替。
struct SpotSwitchSheet: View {
    let spots: [Spot]
    let current: Spot?
    let onSelect: (Spot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ForEach(spots) { s in
                Button { onSelect(s) } label: {
                    HStack {
                        Text(s.name).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        if s.id == current?.id { Circle().fill(DS.Color.accent).frame(width: 8, height: 8) }
                    }
                    .padding(DS.Spacing.m)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if spots.isEmpty { Text("釣行が始まると釣り場が登録されます").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
    }
}
