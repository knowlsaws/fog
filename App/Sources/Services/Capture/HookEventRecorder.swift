import Foundation
import Core

/// 針ロスト・針追加の記録（例外的入力。撮影画面の長押しメニュー・ウィジェット）。位置と時刻は自動。
@MainActor
struct HookEventRecorder {
    let store: FogStore
    let detection: SessionDetectionService
    let scheduler: SnapshotScheduler
    let capture: CaptureService
    var inventory: InventoryStore? = nil

    @discardableResult
    func record(_ kind: HookEvent.Kind, at date: Date = .now) -> HookEvent? {
        guard let active = try? store.activeSession() else { return nil }
        let coordinate = scheduler.currentCoordinate ?? active.track.last?.coordinate ?? (try? store.spot(id: active.spotID))?.coordinate
        guard let coordinate else { return nil }
        let rigID = capture.currentRigID ?? active.rigID
        let event = HookEvent(sessionID: active.id, pointID: detection.currentPointID(), at: date, coordinate: coordinate, kind: kind, rigID: rigID)
        try? store.upsert(event)
        // 在庫（F-26）：ロストでそのリグのシンカーとフックを 1 つ減らす
        if kind == .lost { inventory?.consumeHookLost(rigID: rigID) }
        return event
    }
}
