import SwiftUI

/// デザイントークン。docs/02_ui_design.md §1 が正。
enum DS {
    enum Color {
        static let background = SwiftUI.Color(red: 0.043, green: 0.043, blue: 0.047)   // #0B0B0C
        static let surface = SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.12)
        static let surfaceRaised = SwiftUI.Color(red: 0.16, green: 0.16, blue: 0.17)
        static let accent = SwiftUI.Color(red: 1.0, green: 0.478, blue: 0.102)          // #FF7A1A
        static let secondary = SwiftUI.Color(red: 0.45, green: 0.62, blue: 0.47)        // muted green
        static let textPrimary = SwiftUI.Color.white
        static let textSecondary = SwiftUI.Color.white.opacity(0.7)
        static let textTertiary = SwiftUI.Color.white.opacity(0.4)
        /// 予報が届かない先・低確信度
        static let faded = SwiftUI.Color.white.opacity(0.25)
        /// 月相アイコン（確定画像の薄い紫）
        static let moon = SwiftUI.Color(red: 0.56, green: 0.52, blue: 0.85)
        /// グラフのパネル・チップの枠なし面（#1C1C1E 相当）
        static let panel = SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    enum Font {
        static func score(_ size: CGFloat = 96) -> SwiftUI.Font { .system(size: size, weight: .bold, design: .rounded) }
        static func number(_ size: CGFloat = 20) -> SwiftUI.Font { .system(size: size, weight: .semibold, design: .rounded) }
        static let label = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 20
        static let chip: CGFloat = 14
    }
}
