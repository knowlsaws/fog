import Foundation

/// 端末気圧計の履歴から直近 3 時間の傾向（hPa の変化量）を出す。
public enum PressureTrend {
    /// `samples` は時刻順でなくてよい。3 時間前の値が無ければ最古（1 時間以上前）との差を 3 時間換算する。
    public static func threeHourChange(_ samples: [PressureSample], now: Date) -> Double? {
        let sorted = samples.filter { $0.at <= now }.sorted { $0.at < $1.at }
        guard let latest = sorted.last else { return nil }
        let target = now.addingTimeInterval(-3 * 3600)
        if let ref = sorted.last(where: { $0.at <= target }) {
            return latest.pressureHPa - ref.pressureHPa
        }
        guard let oldest = sorted.first, latest.at.timeIntervalSince(oldest.at) >= 3600 else { return nil }
        let hours = latest.at.timeIntervalSince(oldest.at) / 3600
        return (latest.pressureHPa - oldest.pressureHPa) / hours * 3
    }

    /// 保持する履歴を 6 時間に刈り込む。
    public static func prune(_ samples: [PressureSample], now: Date, keep: TimeInterval = 6 * 3600) -> [PressureSample] {
        samples.filter { $0.at >= now.addingTimeInterval(-keep) && $0.at <= now }.sorted { $0.at < $1.at }
    }
}
