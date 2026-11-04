import Foundation

/// 統計・相関（L8 で実装）。L0 は骨組み。
public enum Analytics {
    public struct SpotStats: Sendable {
        public var sessions: Int
        public var catches: Int
        public var catchesPerHour: Double
        public var blankRate: Double
    }

    public static func spotStats(sessions: [Session]) -> SpotStats {
        let catches = sessions.reduce(0) { $0 + $1.catches.count }
        let hours = sessions.reduce(0.0) { acc, s in
            acc + ((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 3600)
        }
        let blanks = sessions.filter(\.isBlank).count
        return SpotStats(
            sessions: sessions.count,
            catches: catches,
            catchesPerHour: hours > 0 ? Double(catches) / hours : 0,
            blankRate: sessions.isEmpty ? 0 : Double(blanks) / Double(sessions.count)
        )
    }
}
