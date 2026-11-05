import Foundation

/// シンカー・フック・ワームの在庫（F-26）。針ロストの記録で、そのリグに紐付く在庫が減る。
public struct InventoryItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case sinker, hook, worm, other
        public var label: String {
            switch self {
            case .sinker: return "シンカー"
            case .hook: return "フック"
            case .worm: return "ワーム"
            case .other: return "その他"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var count: Int
    /// この数以下になったら知らせる
    public var lowThreshold: Int
    /// 紐付くリグ（針ロストで減らす）。nil なら手動だけ
    public var rigID: UUID?

    public init(id: UUID = UUID(), name: String, kind: Kind, count: Int, lowThreshold: Int = 3, rigID: UUID? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.count = count; self.lowThreshold = lowThreshold; self.rigID = rigID
    }

    public var isLow: Bool { count <= lowThreshold }
}

public enum Inventory {
    /// 針ロスト 1 回：そのリグに紐付くシンカーとフックを 1 つずつ減らす。返り値は（更新後の一覧, 今回しきい値を下回った品目）
    public static func consumeHookLost(_ items: [InventoryItem], rigID: UUID?) -> (items: [InventoryItem], nowLow: [InventoryItem]) {
        guard let rigID else { return (items, []) }
        var nowLow: [InventoryItem] = []
        let updated = items.map { item -> InventoryItem in
            guard item.rigID == rigID, item.kind == .sinker || item.kind == .hook, item.count > 0 else { return item }
            var i = item
            let wasLow = i.isLow
            i.count -= 1
            if i.isLow, !wasLow { nowLow.append(i) }
            return i
        }
        return (updated, nowLow)
    }
}
