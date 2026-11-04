import Foundation

/// ダミーデータ。初回起動時のストア確認（L1 受け入れ条件）と SwiftUI プレビュー、テストに使う。
/// 値はすべて固定（UUID・時刻）なので、JSON フィクスチャと比較できる。
public enum SampleData {
    public static let spotID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    public static let sessionID = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
    public static let catchID = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
    public static let snapshotID = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
    public static let catchEnvID = UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!
    public static let hookEventID = UUID(uuidString: "E0000000-0000-4000-8000-000000000001")!
    public static let tackleID = UUID(uuidString: "F0000000-0000-4000-8000-000000000001")!
    public static let rigID = UUID(uuidString: "F0000000-0000-4000-8000-000000000002")!
    public static let pointID = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!

    /// 函館港（西埠頭付近）。
    public static let hakodate = Coordinate(latitude: 41.7822, longitude: 140.7192)

    /// 2026-10-18 05:30 JST
    public static let startedAt = Date(timeIntervalSince1970: 1_792_269_000)
    /// 2026-10-18 06:12 JST
    public static let caughtAt = Date(timeIntervalSince1970: 1_792_271_520)
    /// 2026-10-18 06:40 JST
    public static let hookLostAt = Date(timeIntervalSince1970: 1_792_273_200)
    /// 2026-10-18 08:10 JST
    public static let endedAt = Date(timeIntervalSince1970: 1_792_278_600)
    /// 2026-01-10 12:00 JST（登録日）
    public static let registeredAt = Date(timeIntervalSince1970: 1_768_014_000)

    public static func spot() -> Spot {
        Spot(id: spotID, name: "函館港", coordinate: hakodate, isRegistered: true, createdAt: registeredAt)
    }

    public static func point() -> Point {
        Point(id: pointID, spotID: spotID, coordinate: hakodate, meshKey: nil, createdAt: startedAt)
    }

    public static func tackle() -> Tackle {
        Tackle(id: tackleID, kind: .bait, name: "ベイト", rod: "ロックフィッシュ 7.6ft", reel: "ベイトリール", line: "PE1.5 + 20lb", createdAt: registeredAt)
    }

    public static func rig() -> Rig {
        Rig(id: rigID, sinkerGrams: 14, hookSize: "#1", worm: "バグアンツ3\"", sortOrder: 0)
    }

    public static func snapshot(id: UUID, at: Date, isForecast: Bool) -> EnvSnapshot {
        var env = EnvSnapshot(id: id, at: at, coordinate: hakodate, isForecast: isForecast)
        env.airTemperatureC = 11.5
        env.humidity = 0.78
        env.conditionCode = "partlyCloudy"
        env.windSpeedMS = 2.4
        env.windGustMS = 4.1
        env.windDirectionDeg = 300
        env.pressureHPa = 1014.2
        env.cloudCover = 0.4
        env.precipitationMM = 0
        env.measuredPressureHPa = 1013.9
        env.pressureTrend3hHPa = -0.8
        env.tideLevelCm = 62
        env.tideRateCmPerHour = 9.5
        env.tideName = "中潮"
        env.waveHeightM = 0.3
        env.wavePeriodS = 4.2
        env.seaSurfaceTempC = 15.8
        env.moonAge = 7.1
        return env
    }

    public static func catchRecord() -> Catch {
        Catch(
            id: catchID,
            sessionID: sessionID,
            at: caughtAt,
            coordinate: hakodate,
            species: "アイナメ",
            speciesConfidence: 0.92,
            lengthCm: 38,
            lengthErrorCm: 1.5,
            photoLocalIdentifier: nil,
            tackle: .bait,
            rigID: rigID,
            env: snapshot(id: catchEnvID, at: caughtAt, isForecast: false),
            released: true,
            pointID: pointID,
            speciesCandidates: [
                SpeciesCandidate(species: "アイナメ", confidence: 0.92),
                SpeciesCandidate(species: "クジメ", confidence: 0.05),
                SpeciesCandidate(species: "ホッケ", confidence: 0.02),
            ],
            speciesCorrected: false,
            photoLocalIdentifiers: [],
            tackleID: tackleID
        )
    }

    public static func hookEvent() -> HookEvent {
        HookEvent(id: hookEventID, sessionID: sessionID, pointID: pointID, at: hookLostAt, coordinate: hakodate, kind: .lost, rigID: rigID)
    }

    /// 函館港・朝マズメの釣行。アイナメ 38cm を1尾、針ロスト1回。
    public static func session() -> Session {
        Session(
            id: sessionID,
            spotID: spotID,
            startedAt: startedAt,
            endedAt: endedAt,
            snapshots: [snapshot(id: snapshotID, at: startedAt, isForecast: false)],
            catches: [catchRecord()],
            tackle: .bait,
            rigID: rigID,
            hookEvents: [hookEvent()],
            track: [
                TrackSample(at: startedAt, coordinate: hakodate),
                TrackSample(at: caughtAt, coordinate: Coordinate(latitude: 41.7824, longitude: 140.7195)),
            ],
            tackleID: tackleID,
            isAutoDetected: true,
            activity: ActivitySummary(stepCount: 1850, walkingDistanceM: 1200),
            report: SessionReport(summary: "上げ潮の朝マズメに1尾", body: "ダミー釣行です。L8 で Foundation Models が生成します。", generatedAt: endedAt)
        )
    }
}
