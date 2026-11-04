import Foundation

/// エクスポート／インポート（F-23、§6）。JSON は Core のモデルをそのまま、CSV は釣果・釣行・スナップショットの 3 表。
public struct ExportBundle: Codable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var spots: [Spot]
    public var sessions: [Session]
    public var points: [Point]
    public var tackles: [Tackle]
    public var rigs: [Rig]
    public var species: [Species]

    public init(exportedAt: Date = .now, spots: [Spot], sessions: [Session], points: [Point] = [], tackles: [Tackle] = [], rigs: [Rig] = [], species: [Species] = []) {
        version = 1
        self.exportedAt = exportedAt
        self.spots = spots; self.sessions = sessions; self.points = points; self.tackles = tackles; self.rigs = rigs; self.species = species
    }

    public func jsonData() throws -> Data { try FogJSON.encode(self) }
    public static func from(json: Data) throws -> ExportBundle { try FogJSON.decode(ExportBundle.self, from: json) }
}

public enum CSVExport {
    static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }
    static func num(_ d: Double?) -> String { d.map { String($0) } ?? "" }
    static func date(_ d: Date?) -> String { d.map { FogJSON.format($0) } ?? "" }

    /// 釣果（1 行 1 尾）
    public static func catches(_ sessions: [Session], spots: [Spot]) -> String {
        let spotName = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0.name) })
        var rows = ["catch_id,session_id,spot,at,latitude,longitude,species,confidence,length_cm,length_error_cm,tackle,rig_id,released,photo,tide_name,tide_level_cm,tide_rate_cm_h,wind_ms,air_temp_c,sea_temp_c,pressure_hpa,pressure_trend_3h,wave_m,moon_age"]
        for s in sessions {
            for c in s.catches {
                let e = c.env
                rows.append([c.id.uuidString, s.id.uuidString, esc(spotName[s.spotID] ?? ""), date(c.at), String(c.coordinate.latitude), String(c.coordinate.longitude),
                             esc(c.species), String(c.speciesConfidence), num(c.lengthCm), num(c.lengthErrorCm), c.tackle?.rawValue ?? "", c.rigID?.uuidString ?? "",
                             String(c.released), c.photoLocalIdentifier ?? "", e?.tideName ?? "", num(e?.tideLevelCm), num(e?.tideRateCmPerHour), num(e?.windSpeedMS),
                             num(e?.airTemperatureC), num(e?.seaSurfaceTempC), num(e?.measuredPressureHPa ?? e?.pressureHPa), num(e?.pressureTrend3hHPa), num(e?.waveHeightM), num(e?.moonAge)].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// 釣行（1 行 1 釣行）
    public static func sessions(_ sessions: [Session], spots: [Spot]) -> String {
        let spotName = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0.name) })
        var rows = ["session_id,spot,started_at,ended_at,hours,catches,hook_losses,auto_detected,steps,walking_m,report_summary"]
        for s in sessions {
            rows.append([s.id.uuidString, esc(spotName[s.spotID] ?? ""), date(s.startedAt), date(s.endedAt), num(s.duration.map { $0 / 3600 }), String(s.catches.count),
                         String(s.hookEvents.filter { $0.kind == .lost }.count), String(s.isAutoDetected), s.activity?.stepCount.map(String.init) ?? "",
                         num(s.activity?.walkingDistanceM), esc(s.report?.summary ?? "")].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// 環境スナップショット（1 行 1 スナップショット）
    public static func snapshots(_ sessions: [Session]) -> String {
        var rows = ["session_id,at,latitude,longitude,is_forecast,air_temp_c,humidity,condition,wind_ms,gust_ms,wind_dir,pressure_hpa,measured_pressure_hpa,pressure_trend_3h,cloud,precip_mm,tide_level_cm,tide_rate_cm_h,tide_name,wave_m,wave_period_s,sea_temp_c,moon_age"]
        for s in sessions {
            for e in s.snapshots {
                rows.append([s.id.uuidString, date(e.at), String(e.coordinate.latitude), String(e.coordinate.longitude), String(e.isForecast), num(e.airTemperatureC), num(e.humidity),
                             e.conditionCode ?? "", num(e.windSpeedMS), num(e.windGustMS), num(e.windDirectionDeg), num(e.pressureHPa), num(e.measuredPressureHPa), num(e.pressureTrend3hHPa),
                             num(e.cloudCover), num(e.precipitationMM), num(e.tideLevelCm), num(e.tideRateCmPerHour), e.tideName ?? "", num(e.waveHeightM), num(e.wavePeriodS), num(e.seaSurfaceTempC), num(e.moonAge)].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
