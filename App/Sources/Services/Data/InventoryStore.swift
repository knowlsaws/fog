import Foundation
import Core

/// 在庫（F-26）の保存。JSON 1 ファイル。針ロストで減らし、しきい値を下回ったら通知する。
@MainActor
@Observable
final class InventoryStore {
    private(set) var items: [InventoryItem] = []
    private var url: URL { FogShared.containerURL.appendingPathComponent("inventory.json") }

    init() { load() }

    func upsert(_ item: InventoryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        save()
    }

    func delete(id: UUID) { items.removeAll { $0.id == id }; save() }

    func adjust(id: UUID, by delta: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].count = max(0, items[i].count + delta)
        save()
    }

    /// 針ロスト 1 回分を減らし、今回しきい値を下回った品目を知らせる
    func consumeHookLost(rigID: UUID?) {
        let r = Inventory.consumeHookLost(items, rigID: rigID)
        guard r.items != items else { return }
        items = r.items
        save()
        for low in r.nowLow { SessionNotifications.inventoryLow(low) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let list = try? FogJSON.decode([InventoryItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        guard let data = try? FogJSON.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
