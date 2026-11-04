import Foundation
import AppIntents
import WidgetKit
import Core

/// 中ウィジェットの「タックル切替」。アプリを開かずに切り替える（F-14 の例外的入力）。
struct ToggleTackleIntent: AppIntent {
    static let title: LocalizedStringResource = "タックル切替"
    static let description = IntentDescription("スピニングとベイトを切り替える")

    func perform() async throws -> some IntentResult {
        FogShared.toggleTackle()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// 中ウィジェットの「針ロスト」。時刻だけ記録し、位置はアプリが次に前面に来たときに釣行の軌跡から補う（F-15）。
struct HookLostIntent: AppIntent {
    static let title: LocalizedStringResource = "針ロスト"
    static let description = IntentDescription("根掛かりで針を失ったことを記録する")

    func perform() async throws -> some IntentResult {
        FogShared.enqueueHookLost()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
