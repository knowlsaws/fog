import Foundation
import XCTest
@testable import Core

final class TideEngineTests: XCTestCase {
    let jst = TimeZone(identifier: "Asia/Tokyo")!

    func testConstituentSpeeds() {
        XCTAssertEqual(ConstituentTable.speedDegPerHour("M2")!, 28.9841042, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("S2")!, 30.0, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("K1")!, 15.0410686, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("O1")!, 13.9430356, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("N2")!, 28.4397295, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("M4")!, 57.9682084, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("Sa")!, 0.0410686, accuracy: 0.0005)
        XCTAssertEqual(ConstituentTable.speedDegPerHour("MSf")!, 1.0158958, accuracy: 0.0005)
    }

    func testAllSixtyConstituentsAreDefined() {
        let jma = ["Sa", "Ssa", "Mm", "MSf", "Mf", "2Q1", "σ1", "Q1", "ρ1", "O1", "MP1", "M1", "χ1", "π1", "P1", "S1", "K1", "ψ1", "φ1",
                   "θ1", "J1", "SO1", "OO1", "OQ2", "MNS2", "2N2", "μ2", "N2", "ν2", "OP2", "M2", "MKS2", "λ2", "L2", "T2", "S2", "R2",
                   "K2", "MSN2", "KJ2", "2SM2", "MO3", "M3", "SO3", "MK3", "SK3", "MN4", "M4", "SN4", "MS4", "MK4", "S4", "SK4",
                   "2MN6", "M6", "MSN6", "2MS6", "2MK6", "2SM6", "MSK6"]
        XCTAssertEqual(jma.count, 60)
        let args = AstronomicalArguments(at: Date(timeIntervalSince1970: 1_792_269_000))
        for name in jma {
            XCTAssertNotNil(args.argument(for: name), name)
        }
        XCTAssertEqual(ConstituentTable.canonicalName("SIG1"), "σ1")
        XCTAssertEqual(ConstituentTable.canonicalName("LAM2"), "λ2")
    }

    func testSingleM2StationHasSemidiurnalPeriod() {
        let station = TideStation(id: "XX", name: "test", coordinate: .init(latitude: 41.78, longitude: 140.72),
                                  meanSeaLevelCm: 100, constituents: [TidalConstituent(name: "M2", amplitudeCm: 50, phaseLagDeg: 120)])
        let engine = TideEngine(station: station)
        let from = Date(timeIntervalSince1970: 1_792_269_000)
        let ext = engine.extremes(from: from, to: from.addingTimeInterval(2 * 86_400))
        let highs = ext.filter { $0.kind == .high }
        XCTAssertGreaterThanOrEqual(highs.count, 3)
        for (a, b) in zip(highs, highs.dropFirst()) {
            XCTAssertEqual(b.at.timeIntervalSince(a.at) / 3600, 12.4206, accuracy: 0.05)
        }
        // 振幅は f × H（f は 0.96〜1.04）
        let amp = highs[0].levelCm - 100
        XCTAssertEqual(amp, 50, accuracy: 2.5)
        // 変化率は満潮で 0 付近
        XCTAssertEqual(engine.rate(at: highs[0].at), 0, accuracy: 1)
    }

    func testNearestStation() {
        let a = TideStation(id: "A", name: "函館", coordinate: .init(latitude: 41.78, longitude: 140.72), meanSeaLevelCm: 0, constituents: [TidalConstituent(name: "M2", amplitudeCm: 1, phaseLagDeg: 0)])
        let b = TideStation(id: "B", name: "東京", coordinate: .init(latitude: 35.65, longitude: 139.77), meanSeaLevelCm: 0, constituents: [TidalConstituent(name: "M2", amplitudeCm: 1, phaseLagDeg: 0)])
        let c = TideStation(id: "C", name: "分潮なし", coordinate: .init(latitude: 41.79, longitude: 140.73), meanSeaLevelCm: 0, constituents: [])
        let catalog = TideCatalog(year: 2026, source: "", stations: [a, b, c])
        XCTAssertEqual(catalog.nearest(to: .init(latitude: 41.80, longitude: 140.80))?.id, "A")
        XCTAssertEqual(catalog.nearest(to: .init(latitude: 35.0, longitude: 139.0))?.id, "B")
        XCTAssertEqual(catalog.nearest(to: .init(latitude: 41.80, longitude: 140.80), count: 2).map(\.id), ["C", "A"])
    }

    func testGeoDistance() {
        let d = Geo.distanceMeters(.init(latitude: 41.7687, longitude: 140.7288), .init(latitude: 35.6895, longitude: 139.7692))
        XCTAssertEqual(d, 681_000, accuracy: 5_000)
    }

    func testJMATideTableParser() {
        var line = ""
        for h in 0..<24 { line += String(format: "%3d", 100 + h) }
        // 満潮・干潮は「時刻4桁＋潮位3桁」の 7 桁 × 4 組
        line += "261018HK" + "0612180" + "1830175" + "9999999" + "9999999" + "0030 20" + "1245 25" + "9999999" + "9999999"
        let days = JMATideTableParser.parse(line + "\n")
        XCTAssertEqual(days.count, 1)
        let d = days[0]
        XCTAssertEqual(d.stationCode, "HK")
        XCTAssertEqual(d.date.year, 2026); XCTAssertEqual(d.date.month, 10); XCTAssertEqual(d.date.day, 18)
        XCTAssertEqual(d.hourlyLevelsCm[0], 100)
        XCTAssertEqual(d.hourlyLevelsCm[23], 123)
        XCTAssertEqual(d.highTides.count, 2)
        XCTAssertEqual(d.lowTides.count, 2)
        XCTAssertEqual(d.highTides[0].levelCm, 180)
        XCTAssertEqual(d.lowTides[1].time.hour, 12)
        XCTAssertEqual(d.hourlySamples().count, 24)
        XCTAssertEqual(d.extremes().count, 4)
    }

    /// L2 受け入れ条件: 函館の推算値が気象庁潮位表（毎時潮位・満干）と数 cm・数分以内で一致する。
    /// フィクスチャ（tide-data ワークフローが取得）と同梱データが揃ったときだけ走る。
    func testBundledHarmonicsAgainstJMATables() throws {
        let catalog = TideCatalog.bundled()
        let fixturesDir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fixturesDir.path)) ?? []
        let tables = names.filter { $0.hasPrefix("jma_tide_") && $0.hasSuffix(".txt") }.sorted()
            .map { fixturesDir.appendingPathComponent($0) }
        try XCTSkipIf(catalog.stations.isEmpty || tables.isEmpty, "harmonics.json かフィクスチャが未取得")
        var checked = 0
        for url in tables {
            let text = try String(contentsOf: url, encoding: .utf8)
            let days = JMATideTableParser.parse(text)
            guard let code = days.first?.stationCode,
                  let station = catalog.stations.first(where: { $0.id == code }), !station.constituents.isEmpty else {
                XCTFail("フィクスチャ \(url.lastPathComponent) に対応する分潮データがない")
                continue
            }
            let engine = TideEngine(station: station)
            XCTAssertTrue(engine.unknownConstituents.isEmpty, "未知の分潮: \(engine.unknownConstituents)")
            var sumSq = 0.0, maxAbs = 0.0, n = 0
            for day in days {
                for (date, level) in day.hourlySamples() {
                    let diff = engine.level(at: date) - level
                    sumSq += diff * diff; maxAbs = max(maxAbs, abs(diff)); n += 1
                }
            }
            let rms = sqrt(sumSq / Double(max(1, n)))
            // 満干時刻：平坦な極値（小潮・混合潮）は 1 cm で数十分動くので、前後との潮位差が 30 cm 以上の満干だけ比べる
            var timeErrors: [Double] = [], levelErrors: [Double] = []
            for day in days.prefix(120) {
                guard let start = day.dayStart() else { continue }
                let predicted = engine.extremes(from: start.addingTimeInterval(-3 * 3600), to: start.addingTimeInterval(27 * 3600))
                let table = day.extremes().sorted { $0.0 < $1.0 }
                for (i, (at, level, isHigh)) in table.enumerated() {
                    let neighbours = [i > 0 ? table[i - 1].1 : nil, i + 1 < table.count ? table[i + 1].1 : nil].compactMap { $0 }
                    guard let range = neighbours.map({ abs($0 - level) }).max(), range >= 30 else { continue }
                    let same = predicted.filter { ($0.kind == .high) == isHigh && abs($0.at.timeIntervalSince(at)) <= 3 * 3600 }
                    guard let nearest = same.min(by: { abs($0.at.timeIntervalSince(at)) < abs($1.at.timeIntervalSince(at)) }) else { continue }
                    timeErrors.append(abs(nearest.at.timeIntervalSince(at)) / 60)
                    levelErrors.append(abs(nearest.levelCm - level))
                }
            }
            let meanTime = timeErrors.reduce(0, +) / Double(max(1, timeErrors.count))
            let maxTime = timeErrors.max() ?? 0
            print("TIDE CHECK \(station.name)(\(code)): hourly n=\(n) rms=\(String(format: "%.1f", rms))cm max=\(String(format: "%.1f", maxAbs))cm; extremes n=\(timeErrors.count) meanTime=\(String(format: "%.1f", meanTime))min maxTime=\(String(format: "%.1f", maxTime))min meanLevel=\(String(format: "%.1f", levelErrors.reduce(0, +) / Double(max(1, levelErrors.count))))cm")
            XCTAssertLessThan(rms, 5, "\(station.name) 毎時潮位 RMS")
            XCTAssertLessThan(maxAbs, 20, "\(station.name) 毎時潮位 最大差")
            XCTAssertLessThan(meanTime, 6, "\(station.name) 満干時刻 平均差（分）")
            XCTAssertLessThan(maxTime, 30, "\(station.name) 満干時刻 最大差（分）")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
