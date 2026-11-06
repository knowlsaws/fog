import SwiftUI
import UIKit

/// テーマ（F-49）。`dark` が従来の標準。`grimoire`（魔導書）は個人利用向けの画像テーマで、
/// `App/Resources/Themes/grimoire/` に置いた画像があればそれを使い、無ければ色だけで成立する。
enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case grimoire

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: return "ダーク"
        case .grimoire: return "魔導書"
        }
    }

    /// 画像テーマか（画像フォルダを持つ）
    var hasAssets: Bool { self != .dark }

    var palette: ThemePalette {
        switch self {
        case .dark: return .dark
        case .grimoire: return .grimoire
        }
    }

    /// 文字のデザイン。魔導書はセリフ体（New York）
    var fontDesign: Font.Design {
        switch self {
        case .dark: return .default
        case .grimoire: return .serif
        }
    }

    var numberDesign: Font.Design {
        switch self {
        case .dark: return .rounded
        case .grimoire: return .serif
        }
    }
}

struct ThemePalette {
    var background: Color
    var surface: Color
    var surfaceRaised: Color
    var accent: Color
    var secondary: Color
    var sun: Color
    var daylight: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var faded: Color
    var sea: Color
    var moon: Color
    var saturday: Color
    var holiday: Color
    var panel: Color
    /// 画像の上に敷く暗幕の濃さ（0 で無し）。文字の読みやすさのため
    var scrim: Double

    static let dark = ThemePalette(
        background: Color(red: 0.043, green: 0.043, blue: 0.047),   // #0B0B0C
        surface: Color(red: 0.11, green: 0.11, blue: 0.12),
        surfaceRaised: Color(red: 0.16, green: 0.16, blue: 0.17),
        accent: Color(red: 0.45, green: 0.62, blue: 0.47),          // #739E78
        secondary: Color(red: 0.45, green: 0.62, blue: 0.47),
        sun: Color(red: 0.96, green: 0.77, blue: 0.26),             // #F5C542
        daylight: Color(red: 1.0, green: 0.478, blue: 0.102),       // #FF7A1A
        textPrimary: .white,
        textSecondary: .white.opacity(0.7),
        textTertiary: .white.opacity(0.4),
        faded: .white.opacity(0.25),
        sea: Color(red: 0.30, green: 0.62, blue: 0.95),
        moon: Color(red: 0.56, green: 0.52, blue: 0.85),
        saturday: Color(red: 0.36, green: 0.64, blue: 1.0),         // #5CA3FF
        holiday: Color(red: 1.0, green: 0.36, blue: 0.36),          // #FF5C5C
        panel: Color(red: 0.11, green: 0.11, blue: 0.12),
        scrim: 0
    )

    /// 魔導書：深い紺の夜空に金とエメラルド。面は半透明のガラスで背景画像を透かす
    static let grimoire = ThemePalette(
        background: Color(red: 0.055, green: 0.082, blue: 0.15),    // #0E1526
        surface: Color(red: 0.10, green: 0.13, blue: 0.22).opacity(0.88),
        surfaceRaised: Color(red: 0.17, green: 0.20, blue: 0.32),
        accent: Color(red: 0.84, green: 0.70, blue: 0.40),          // 金 #D6B366
        secondary: Color(red: 0.31, green: 0.75, blue: 0.60),       // エメラルド #4FBF9A
        sun: Color(red: 0.98, green: 0.80, blue: 0.36),
        daylight: Color(red: 1.0, green: 0.55, blue: 0.20),
        textPrimary: Color(red: 0.95, green: 0.91, blue: 0.80),     // クリーム #F3E9CC
        textSecondary: Color(red: 0.95, green: 0.91, blue: 0.80).opacity(0.72),
        textTertiary: Color(red: 0.95, green: 0.91, blue: 0.80).opacity(0.45),
        faded: Color(red: 0.95, green: 0.91, blue: 0.80).opacity(0.25),
        sea: Color(red: 0.44, green: 0.71, blue: 1.0),
        moon: Color(red: 0.71, green: 0.61, blue: 1.0),
        saturday: Color(red: 0.44, green: 0.71, blue: 1.0),
        holiday: Color(red: 1.0, green: 0.45, blue: 0.45),
        panel: Color(red: 0.10, green: 0.13, blue: 0.22).opacity(0.80),
        scrim: 0.30
    )
}

/// 選択中のテーマ。`@Observable` なので、`DS.Color.*` を読む全ビューが切替で再描画される
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let key = "fog.theme"

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            ThemeAssets.clear()
        }
    }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .dark
    }
}

/// テーマ画像の読み込み。`Themes/<theme>/<name>.(png|jpg|jpeg)` をバンドルから探す。無ければ nil
@MainActor
enum ThemeAssets {
    /// 画面ごとの画像名（開発者が用意するファイル名）
    enum Name: String, CaseIterable {
        case bgHome = "bg_home"
        case bgLog = "bg_log"
        case bgGuide = "bg_guide"
        case bgSpots = "bg_spots"
        case bgSheet = "bg_sheet"
        case tabbar = "tabbar"
        case tabHome = "tab_home"
        case tabLog = "tab_log"
        case tabCamera = "tab_camera"
        case tabGuide = "tab_guide"
        case tabSpots = "tab_spots"
        case ringHome = "ring_home"

        var note: String {
            switch self {
            case .bgHome: return "ホームの背景（縦 9:16）"
            case .bgLog: return "ログの背景（縦 9:16）"
            case .bgGuide: return "図鑑の背景（縦 9:16）"
            case .bgSpots: return "釣り場の一覧シートの背景（縦 9:16）"
            case .bgSheet: return "設定・各シートの背景（縦 9:16）"
            case .tabbar: return "タブバーの帯（横 3:1）"
            case .tabHome: return "タブ：ホーム（正方形・黒背景）"
            case .tabLog: return "タブ：ログ（正方形・黒背景）"
            case .tabCamera: return "タブ：撮影（正方形・黒背景）"
            case .tabGuide: return "タブ：図鑑（正方形・黒背景）"
            case .tabSpots: return "タブ：釣り場（正方形・黒背景）"
            case .ringHome: return "ホームの釣れ率の飾り枠（正方形・黒背景）"
            }
        }
    }

    private static var cache: [String: UIImage?] = [:]

    static func clear() { cache.removeAll() }

    static func image(_ name: Name) -> UIImage? { image(name, theme: ThemeStore.shared.theme) }
    static func has(_ name: Name) -> Bool { image(name) != nil }

    static func image(_ name: Name, theme: AppTheme) -> UIImage? {
        guard theme.hasAssets else { return nil }
        let key = "\(theme.rawValue)/\(name.rawValue)"
        if let cached = cache[key] { return cached }
        var found: UIImage?
        for ext in ["png", "jpg", "jpeg"] {
            if let url = Bundle.main.url(forResource: name.rawValue, withExtension: ext, subdirectory: "Themes/\(theme.rawValue)"),
               let image = UIImage(contentsOfFile: url.path) {
                found = image
                break
            }
        }
        cache[key] = found
        return found
    }

    static func has(_ name: Name, theme: AppTheme) -> Bool { image(name, theme: theme) != nil }
}

/// 画面の背景：テーマ画像があれば全面に敷き（はみ出しは切る）、暗幕を重ねる。無ければテーマの背景色
struct ThemeBackground: View {
    let name: ThemeAssets.Name
    var scrim: Double? = nil

    var body: some View {
        let theme = ThemeStore.shared.theme
        ZStack {
            theme.palette.background
            if let image = ThemeAssets.image(name, theme: theme) {
                GeometryReader { geo in
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                Color.black.opacity(scrim ?? theme.palette.scrim)
            }
        }
        .ignoresSafeArea()
    }
}

/// 黒背景で描かれた飾り画像（タブのアイコン・飾り枠）を、黒を透かして重ねる
struct ThemeOrnament: View {
    let name: ThemeAssets.Name
    var body: some View {
        if let image = ThemeAssets.image(name) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).blendMode(.screen)
        }
    }
}
