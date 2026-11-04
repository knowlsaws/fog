import Foundation

/// 外部 API を 1 時間に 1 回より多く叩かないためのゲート（§7 非機能要件）。
/// キーは「プロバイダ名 + 位置キー」。最終取得時刻は App 側が永続化する。
public struct FetchGate: Codable, Sendable {
    public var minimumInterval: TimeInterval
    public var lastFetch: [String: Date]

    public init(minimumInterval: TimeInterval = 3600, lastFetch: [String: Date] = [:]) {
        self.minimumInterval = minimumInterval
        self.lastFetch = lastFetch
    }

    public func allows(_ key: String, now: Date) -> Bool {
        guard let last = lastFetch[key] else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }

    /// 許可されたら記録して true。
    public mutating func tryAcquire(_ key: String, now: Date) -> Bool {
        guard allows(key, now: now) else { return false }
        lastFetch[key] = now
        return true
    }

    /// 失敗したときに巻き戻す（圏外で即リトライ可能にする）。
    public mutating func release(_ key: String) { lastFetch[key] = nil }

    public func nextAllowed(_ key: String) -> Date? { lastFetch[key]?.addingTimeInterval(minimumInterval) }
}
