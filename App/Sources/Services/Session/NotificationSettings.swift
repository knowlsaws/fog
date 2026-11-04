import Foundation

/// 通知の種類ごとのオンオフ（§8）。既定はすべてオン。
enum NotificationSettings {
    enum Kind: String, CaseIterable, Identifiable {
        case sessionStart, sessionEnd, record, peak
        var id: String { rawValue }

        var title: String {
            switch self {
            case .sessionStart: return "釣行開始"
            case .sessionEnd: return "釣行終了"
            case .record: return "記録更新"
            case .peak: return "釣れ率ピーク"
            }
        }

        var detail: String {
            switch self {
            case .sessionStart: return "記録を始めたとき。誤検出なら通知から停止"
            case .sessionEnd: return "レポートの要約と尾数"
            case .record: return "初魚種・自己記録（アプリを閉じているときだけ）"
            case .peak: return "今日のピークが 80 以上のとき、1 時間前に 1 回"
            }
        }

        fileprivate var key: String { "fog.notify.\(rawValue)" }
    }

    static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.key) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, for kind: Kind) {
        UserDefaults.standard.set(enabled, forKey: kind.key)
    }
}
