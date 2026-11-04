import Foundation

/// 自動開始・終了のしきい値。感度 3 段階（設定画面）。初期値は L16 の実測で確定する。
public struct DetectionSettings: Codable, Hashable, Sendable {
    public enum Sensitivity: String, Codable, CaseIterable, Sendable {
        case low, medium, high
    }

    /// 滞在と判定するまでの時間
    public var dwellToStart: TimeInterval
    /// 滞在中の移動がこの半径に収まっていれば「同じ場所」
    public var dwellRadiusM: Double
    /// 釣り場中心からこれ以上離れたら「離れた」
    public var awayDistanceM: Double
    /// 離れてからこれだけ経てば終了
    public var awayToEnd: TimeInterval
    /// この速度以上が続いたら車での移動とみなす（m/s。7 ≈ 25 km/h）
    public var drivingSpeedMS: Double
    public var drivingToEnd: TimeInterval
    /// ランガン：終了からこの時間内・この距離内で再開したら同じ釣行にまとめる
    public var runAndGunMaxGap: TimeInterval
    public var runAndGunMaxDistanceM: Double
    /// 立ち位置の記録間隔（低頻度）
    public var trackInterval: TimeInterval
    public var trackMinDistanceM: Double

    public init(dwellToStart: TimeInterval, dwellRadiusM: Double, awayDistanceM: Double, awayToEnd: TimeInterval,
                drivingSpeedMS: Double, drivingToEnd: TimeInterval, runAndGunMaxGap: TimeInterval, runAndGunMaxDistanceM: Double,
                trackInterval: TimeInterval = 120, trackMinDistanceM: Double = 20) {
        self.dwellToStart = dwellToStart; self.dwellRadiusM = dwellRadiusM; self.awayDistanceM = awayDistanceM; self.awayToEnd = awayToEnd
        self.drivingSpeedMS = drivingSpeedMS; self.drivingToEnd = drivingToEnd
        self.runAndGunMaxGap = runAndGunMaxGap; self.runAndGunMaxDistanceM = runAndGunMaxDistanceM
        self.trackInterval = trackInterval; self.trackMinDistanceM = trackMinDistanceM
    }

    public static func forSensitivity(_ s: Sensitivity) -> DetectionSettings {
        switch s {
        case .high:
            return DetectionSettings(dwellToStart: 5 * 60, dwellRadiusM: 200, awayDistanceM: 300, awayToEnd: 20 * 60,
                                     drivingSpeedMS: 7, drivingToEnd: 3 * 60, runAndGunMaxGap: 90 * 60, runAndGunMaxDistanceM: 8_000)
        case .medium:
            return DetectionSettings(dwellToStart: 10 * 60, dwellRadiusM: 150, awayDistanceM: 300, awayToEnd: 30 * 60,
                                     drivingSpeedMS: 7, drivingToEnd: 5 * 60, runAndGunMaxGap: 60 * 60, runAndGunMaxDistanceM: 5_000)
        case .low:
            return DetectionSettings(dwellToStart: 20 * 60, dwellRadiusM: 120, awayDistanceM: 400, awayToEnd: 45 * 60,
                                     drivingSpeedMS: 7, drivingToEnd: 8 * 60, runAndGunMaxGap: 45 * 60, runAndGunMaxDistanceM: 3_000)
        }
    }

    public static let `default` = forSensitivity(.medium)
}
