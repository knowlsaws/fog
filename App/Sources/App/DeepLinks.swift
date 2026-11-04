import Foundation
import SwiftUI
import AppIntents
import Core

/// ロック画面・ウィジェット・カメラコントロールから同じ撮影画面を開く（§5「ロック画面・ウィジェットから開いた場合も同じ画面」）。
/// URL スキーム `fog://capture` と App Intent の両方を受ける。
enum DeepLink: Equatable {
    case capture
    case home
    case toggleTackle
    case hookLost

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "fog" else { return nil }
        switch url.host {
        case "capture": return .capture
        case "home": return .home
        case "tackle": return .toggleTackle
        case "hooklost": return .hookLost
        default: return nil
        }
    }

    static let captureURL = URL(string: "fog://capture")!
    static let homeURL = URL(string: "fog://home")!
}

/// アプリ内で共有する「開くべき画面」。
@MainActor
@Observable
final class Router {
    var pending: DeepLink?
}

/// 撮影を開く App Intent（ウィジェットのボタン・ショートカット・カメラコントロール用）。
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "撮影"
    static let description = IntentDescription("釣れた魚を撮影して記録する")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouterHolder.shared.router?.pending = .capture
        return .result()
    }
}

/// カメラコントロール（iPhone 16 Pro の側面ボタン）からアプリのカメラを開く（§8）。
/// 設定 > カメラ > カメラコントロールでこのアプリを選ぶと、ボタンでアプリが起動して撮影画面になる。
struct FogCameraCaptureIntent: CameraCaptureIntent {
    struct AppContext: Codable, Sendable {}
    static let title: LocalizedStringResource = "Fog で撮影"
    static let description = IntentDescription("釣れた魚を撮影して記録する")

    @MainActor
    func perform() async throws -> some IntentResult {
        RouterHolder.shared.router?.pending = .capture
        return .result()
    }
}

/// Intent から Router に届けるための置き場（App が起動時に設定）。
@MainActor
final class RouterHolder {
    static let shared = RouterHolder()
    weak var router: Router?
}
