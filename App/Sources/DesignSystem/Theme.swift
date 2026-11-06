import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

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
        case charHome = "char_home"
        case charLog = "char_log"
        case charGuide = "char_guide"

        /// キャラクターの切り抜き（位置とサイズを設定で微調整できる）
        var isCharacter: Bool { self == .charHome || self == .charLog || self == .charGuide }

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
            case .charHome: return "ホーム：釣れ率の円を両手で囲むキャラクター（横 16:9・マゼンタ背景）"
            case .charLog: return "ログ：右上のキャラクター（縦 3:4・マゼンタ背景）"
            case .charGuide: return "図鑑：右上のキャラクター（縦 3:4・マゼンタ背景）"
            }
        }
    }

    /// 読み込んだ画像と、重ね方（背景の色から自動で決める）
    struct Loaded {
        enum Blend { case opaque, screen, keyed }
        let image: UIImage
        let blend: Blend
    }

    private static var cache: [String: Loaded?] = [:]

    static func clear() { cache.removeAll() }

    static func image(_ name: Name) -> UIImage? { load(name)?.image }
    static func has(_ name: Name) -> Bool { load(name) != nil }
    static func has(_ name: Name, theme: AppTheme) -> Bool { load(name, theme: theme) != nil }
    static func image(_ name: Name, theme: AppTheme) -> UIImage? { load(name, theme: theme)?.image }

    static func load(_ name: Name) -> Loaded? { load(name, theme: ThemeStore.shared.theme) }

    static func load(_ name: Name, theme: AppTheme) -> Loaded? {
        guard theme.hasAssets else { return nil }
        let key = "\(theme.rawValue)/\(name.rawValue)"
        if let cached = cache[key] { return cached }
        var found: Loaded?
        for ext in ["png", "jpg", "jpeg"] {
            if let url = Bundle.main.url(forResource: name.rawValue, withExtension: ext, subdirectory: "Themes/\(theme.rawValue)"),
               let image = UIImage(contentsOfFile: url.path) {
                found = prepare(image)
                break
            }
        }
        cache[key] = found
        return found
    }

    /// 四隅の色で背景を判定する。マゼンタ（#FF00FF 付近）なら透過に抜き、黒なら screen で重ね、それ以外はそのまま
    private static func prepare(_ image: UIImage) -> Loaded {
        guard let corner = cornerColor(image) else { return Loaded(image: image, blend: .opaque) }
        if corner.r > 0.75 && corner.g < 0.35 && corner.b > 0.75 {
            if let keyed = chromaKeyed(image) { return Loaded(image: keyed, blend: .keyed) }
            return Loaded(image: image, blend: .opaque)
        }
        if corner.r < 0.12 && corner.g < 0.12 && corner.b < 0.12 { return Loaded(image: image, blend: .screen) }
        return Loaded(image: image, blend: .opaque)
    }

    /// 四隅 4 点の平均色（0〜1）
    private static func cornerColor(_ image: UIImage) -> (r: Double, g: Double, b: Double)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8 else { return nil }
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        for (x, y) in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)] {
            var px = [UInt8](repeating: 0, count: 4)
            guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.draw(cg, in: CGRect(x: -x, y: -(h - 1 - y), width: w, height: h))
            sum.r += Double(px[0]) / 255; sum.g += Double(px[1]) / 255; sum.b += Double(px[2]) / 255
            count += 1
        }
        guard count > 0 else { return nil }
        return (sum.r / count, sum.g / count, sum.b / count)
    }

    /// マゼンタ系（色相 285〜335°、彩度 0.45 以上、明度 0.35 以上）を透明にする色立方体フィルタ
    private static func chromaKeyed(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let size = 32
        var cube = [Float](repeating: 0, count: size * size * size * 4)
        var i = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1), gf = Float(g) / Float(size - 1), bf = Float(b) / Float(size - 1)
                    let (h, sat, val) = hsv(rf, gf, bf)
                    let isKey = sat >= 0.45 && val >= 0.35 && h >= 285 && h <= 335
                    // 境界は少しだけ半透明にして縁のマゼンタのにじみを減らす
                    let edge = sat >= 0.3 && val >= 0.3 && h >= 275 && h <= 345
                    let alpha: Float = isKey ? 0 : (edge ? 0.5 : 1)
                    cube[i] = rf * alpha; cube[i + 1] = gf * alpha; cube[i + 2] = bf * alpha; cube[i + 3] = alpha
                    i += 4
                }
            }
        }
        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(size)
        filter.cubeData = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        filter.inputImage = CIImage(cgImage: cg)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let out = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func hsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        var h: Float = 0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
            if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    // MARK: キャラクターの位置の微調整（設定 > テーマ）

    static func scale(_ name: Name) -> Double {
        let v = UserDefaults.standard.double(forKey: "fog.theme.\(name.rawValue).scale")
        return v == 0 ? 1 : v
    }
    static func offset(_ name: Name) -> CGSize {
        CGSize(width: UserDefaults.standard.double(forKey: "fog.theme.\(name.rawValue).dx"),
               height: UserDefaults.standard.double(forKey: "fog.theme.\(name.rawValue).dy"))
    }
    static func setScale(_ name: Name, _ v: Double) { UserDefaults.standard.set(v, forKey: "fog.theme.\(name.rawValue).scale") }
    static func setOffset(_ name: Name, _ v: CGSize) {
        UserDefaults.standard.set(v.width, forKey: "fog.theme.\(name.rawValue).dx")
        UserDefaults.standard.set(v.height, forKey: "fog.theme.\(name.rawValue).dy")
    }
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
        if let loaded = ThemeAssets.load(name) {
            Image(uiImage: loaded.image).resizable().aspectRatio(contentMode: .fit)
                .blendMode(loaded.blend == .screen ? .screen : .normal)
        }
    }
}

/// キャラクターの切り抜き（F-49）。`baseWidth` を基準に、設定の倍率と位置ずらしを掛けて置く。
/// 画面の内容より後ろに置く（`.background(alignment:)` で使う）
struct ThemeCharacter: View {
    let name: ThemeAssets.Name
    let baseWidth: CGFloat
    /// 設定画面で調整中の値を即時に反映するための tick
    var revision: Int = ThemeLayoutTuning.shared.revision

    var body: some View {
        if let loaded = ThemeAssets.load(name) {
            let scale = ThemeAssets.scale(name)
            let offset = ThemeAssets.offset(name)
            Image(uiImage: loaded.image).resizable().aspectRatio(contentMode: .fit)
                .blendMode(loaded.blend == .screen ? .screen : .normal)
                .frame(width: baseWidth * scale)
                .offset(offset)
                .allowsHitTesting(false)
        }
    }
}

/// 設定で倍率・位置を動かしたときに、置いてある画面を再描画させるための観測点
@MainActor
@Observable
final class ThemeLayoutTuning {
    static let shared = ThemeLayoutTuning()
    var revision = 0
}
