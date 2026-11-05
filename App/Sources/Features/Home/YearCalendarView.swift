import SwiftUI
import Core

/// 年間カレンダー（F-33）：今月から 12 か月。各日を最高釣れ率の濃さで塗る。日付の色は週行と同じ（土曜青・日祝赤）。
/// 予報の先は天気が無いので、潮回りと光（マズメ）の良し悪しが主に出る。タップでホームをその日に送る（推移の範囲内だけ）。
struct YearCalendarSheet: View {
    let model: HomeViewModel
    let onPick: (Date) -> Void
    @State private var heat: [Date: Int] = [:]
    @State private var task: Task<Void, Never>?
    /// 魚種別の狙い目（F-40）。空は全体
    @State private var species: String = ""

    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = model.timeZone; return c }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("年間の潮回り").font(DS.Font.number(20)).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                legend
            }
            if !model.speciesScores.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.s) {
                        chip("全部", selected: species.isEmpty) { species = "" }
                        ForEach(model.speciesScores, id: \.species) { s in chip(s.species, selected: species == s.species) { species = s.species } }
                    }
                }
            }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.m), GridItem(.flexible(), spacing: DS.Spacing.m)], spacing: DS.Spacing.m) {
                    ForEach(0..<12, id: \.self) { m in
                        if let start = monthStart(offset: m) { month(start) }
                    }
                }
            }
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
        .onAppear { start() }
        .onChange(of: species) { _, _ in start() }
        .onDisappear { task?.cancel() }
    }

    private func start() {
        task?.cancel()
        heat = [:]
        task = model.yearHeat(species: species.isEmpty ? nil : species) { heat = $0 }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(DS.Font.caption).foregroundStyle(selected ? DS.Color.background : DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.xs)
                .background(selected ? DS.Color.accent : DS.Color.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            ForEach([30, 55, 75, 95], id: \.self) { v in
                RoundedRectangle(cornerRadius: 2).fill(Self.fill(v)).frame(width: 12, height: 12)
            }
            Text("低→高").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func monthStart(offset: Int) -> Date? {
        let cal = calendar
        let comps = cal.dateComponents([.year, .month], from: model.now)
        guard let base = cal.date(from: comps) else { return nil }
        return cal.date(byAdding: .month, value: offset, to: base)
    }

    private func month(_ start: Date) -> some View {
        let cal = calendar
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: start) // 1=日
        let leading = (firstWeekday + 5) % 7 // 月曜始まり
        let comps = cal.dateComponents([.year, .month], from: start)
        let cells: [Date?] = Array(repeating: nil, count: leading) + (0..<days).map { start.addingTimeInterval(Double($0) * 86_400) }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(comps.year ?? 0)/\(comps.month ?? 0)").font(DS.Font.number(12)).foregroundStyle(DS.Color.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(["月", "火", "水", "木", "金", "土", "日"].enumerated()), id: \.offset) { i, w in
                    Text(w).font(.system(size: 7)).foregroundStyle(i == 5 ? DS.Color.saturday : (i == 6 ? DS.Color.holiday : DS.Color.textTertiary))
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 16) }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = calendar
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: day)
        let holiday = c.weekday == 1 || JapaneseHolidays.isHoliday(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        let score = heat[day]
        let inRange = day >= model.rangeStart && day < model.rangeEnd
        return Button { if inRange { onPick(day) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(score.map(Self.fill) ?? DS.Color.surface)
                Text("\(c.day ?? 0)").font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(holiday ? DS.Color.holiday : (c.weekday == 7 ? DS.Color.saturday : DS.Color.textSecondary))
            }
            .frame(height: 16)
            .overlay {
                if cal.isDate(day, inSameDayAs: model.now) { RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
    }

    /// 最高釣れ率 → 塗りの濃さ（4 段階）
    static func fill(_ score: Int) -> Color {
        switch score {
        case ..<40: return DS.Color.accent.opacity(0.12)
        case 40..<60: return DS.Color.accent.opacity(0.3)
        case 60..<80: return DS.Color.accent.opacity(0.6)
        default: return DS.Color.accent
        }
    }
}
