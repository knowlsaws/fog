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
                eventsRow.frame(height: geo.size.height * 0.09)
                ForecastChart(model: model).frame(height: geo.size.height * 0.32)
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
        HStack(spacing: DS.Spacing.s) {
            if model.isRecording {
                PulsingDot()
            }
            Button { showSpots = true } label: {
                Text(model.spot?.name ?? "釣り場").font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
            }
            .buttonStyle(.plain)
            Text(model.now, format: .dateTime.hour().minute()).font(DS.Font.number(13)).foregroundStyle(DS.Color.textTertiary)
            Spacer()
            Image(systemName: MoonSymbol.name(age: model.moonAge)).font(.system(size: 16)).foregroundStyle(DS.Color.textSecondary)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 16)).foregroundStyle(DS.Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 釣れ率

    private var scoreArea: some View {
        Button { showBreakdown = true } label: {
            HStack(alignment: .center, spacing: DS.Spacing.l) {
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(DS.Color.faded, lineWidth: 10)
                    Circle().trim(from: 0, to: CGFloat(model.score?.score ?? 0) / 100)
                        .stroke(model.score?.isForecast == true ? DS.Color.accent.opacity(0.6) : DS.Color.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: model.score?.score)
                    Text("\(model.score?.score ?? 0)")
                        .font(DS.Font.score(72))
                        .foregroundStyle(DS.Color.textPrimary)
                        .contentTransition(.numericText())
                }
                .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(model.speciesScores, id: \.species) { s in
                        HStack(spacing: DS.Spacing.s) {
                            Text("\(s.score)").font(DS.Font.number(18)).foregroundStyle(DS.Color.textPrimary)
                            Text(s.species).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .frame(width: 110, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    // MARK: 今（4 チップ）

    private var chipsRow: some View {
        HStack(spacing: DS.Spacing.s) {
            ForEach(model.chips) { chip in
                Button { chipDetail = chip } label: {
                    VStack(spacing: DS.Spacing.xs) {
                        Image(systemName: chip.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .rotationEffect(chip.kind == .wind ? .degrees((model.windDirectionDeg ?? 0) + 180) : .zero)
                        Text(chip.text).font(DS.Font.caption).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(color(chip.tone))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.s)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(_ tone: HomeViewModel.Chip.Tone) -> Color {
        switch tone {
        case .good: return DS.Color.accent
        case .normal: return DS.Color.textPrimary
        case .bad: return DS.Color.textTertiary
        }
    }

    // MARK: 次（イベント列）

    private var eventsRow: some View {
        HStack(spacing: DS.Spacing.m) {
            ForEach(model.events, id: \.at) { e in
                Button { model.scrollTarget = e.at } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(e.at, format: .dateTime.hour().minute()).font(DS.Font.number(13))
                        Text(e.label).font(DS.Font.caption)
                    }
                    .foregroundStyle(e.isPositive ? DS.Color.accent : DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
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

/// 2 段グラフ：上段 釣れ率、下段 潮位と満干。時間軸は共有、現在はオレンジの縦線、昼夜を背景の明暗で、予報の無い先は薄く。
struct ForecastChart: View {
    let model: HomeViewModel
    @State private var visibleHours: Double = 24
    @State private var scrollPosition: Date = .now

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Chart {
                ForEach(dayShading, id: \.0) { (start, end) in
                    RectangleMark(xStart: .value("s", start), xEnd: .value("e", end), yStart: .value("y0", 0), yEnd: .value("y1", 100))
                        .foregroundStyle(DS.Color.surface.opacity(0.5))
                }
                ForEach(model.timeline, id: \.at) { p in
                    LineMark(x: .value("時刻", p.at), y: .value("釣れ率", p.score))
                        .foregroundStyle(p.isForecast && model.forecastHorizon.map { p.at > $0 } == true ? DS.Color.accent.opacity(0.3) : DS.Color.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                RuleMark(x: .value("今", model.now)).foregroundStyle(DS.Color.accent).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleHours * 3600)
            .chartScrollPosition(x: $scrollPosition)

            Chart {
                ForEach(dayShading, id: \.0) { (start, end) in
                    RectangleMark(xStart: .value("s", start), xEnd: .value("e", end), yStart: .value("y0", tideRange.lowerBound), yEnd: .value("y1", tideRange.upperBound))
                        .foregroundStyle(DS.Color.surface.opacity(0.5))
                }
                ForEach(model.tideCurve) { p in
                    LineMark(x: .value("時刻", p.at), y: .value("潮位", p.levelCm))
                        .foregroundStyle(DS.Color.textSecondary)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(model.tideExtremes, id: \.at) { e in
                    PointMark(x: .value("時刻", e.at), y: .value("潮位", e.levelCm))
                        .foregroundStyle(DS.Color.textPrimary)
                        .symbolSize(18)
                        .annotation(position: e.kind == .high ? .top : .bottom, spacing: 2) {
                            Text(e.at, format: .dateTime.hour().minute()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                }
                RuleMark(x: .value("今", model.now)).foregroundStyle(DS.Color.accent).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: tideRange)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour(), centered: false).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleHours * 3600)
            .chartScrollPosition(x: $scrollPosition)
        }
        .gesture(MagnifyGesture().onChanged { value in
            visibleHours = min(72, max(6, 24 / value.magnification))
        })
        .onAppear { scrollPosition = model.now.addingTimeInterval(-6 * 3600) }
        .onChange(of: model.scrollTarget) { _, target in
            if let target { withAnimation { scrollPosition = target.addingTimeInterval(-visibleHours * 3600 / 2) } }
        }
    }

    private var tideRange: ClosedRange<Double> {
        let levels = model.tideCurve.map(\.levelCm)
        guard let lo = levels.min(), let hi = levels.max(), hi > lo else { return 0...200 }
        return (lo - 10)...(hi + 10)
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

    var body: some View {
        let env = services.environment.snapshot(at: model.now, coordinate: model.coordinate)
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text(chip.text).font(DS.Font.number(28)).foregroundStyle(DS.Color.textPrimary)
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
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.background)
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
