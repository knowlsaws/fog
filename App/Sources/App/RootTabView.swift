import SwiftUI

/// 5タブ。文字ラベルなし、中央は撮影（オレンジの円）。
/// L0 ではプレースホルダー。各画面は Features/ 配下のループで実装する。
struct RootTabView: View {
    enum Tab: Hashable { case home, log, capture, guide, spots }
    @State private var selected: Tab = .home
    @Environment(AppServices.self) private var services

    var body: some View {
        Group {
            switch selected {
            case .home: HomeView()
            case .log: LogView()
            case .capture: CaptureView()
            case .guide: GuideView()
            case .spots: SpotsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenBackground)
        .environment(\.captureTab, { selected = .capture })
        // タブバーは下のセーフエリアとして置く。各画面はタブバーを除いた高さを 100% として使える
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .ignoresSafeArea(.keyboard)
        .onChange(of: services.router.pending) { _, link in
            guard let link else { return }
            switch link {
            case .capture: selected = .capture
            case .home: selected = .home
            case .toggleTackle: services.capture.currentTackle = (services.capture.currentTackle ?? .spinning) == .spinning ? .bait : .spinning
            case .hookLost: services.hookRecorder.record(.lost)
            }
            services.router.pending = nil
        }
        .onAppear {
            if services.router.pending == .capture { selected = .capture; services.router.pending = nil }
        }
        // テーマ切替（F-49）で全画面を作り直す
        .id(ThemeStore.shared.theme)
    }

    /// 画面ごとの背景（テーマ画像があればそれ、無ければ背景色）。地図と撮影は画像を敷かない
    @ViewBuilder private var screenBackground: some View {
        switch selected {
        case .home: ThemeBackground(name: .bgHome)
        case .log: ThemeBackground(name: .bgLog)
        case .guide: ThemeBackground(name: .bgGuide)
        case .capture, .spots: DS.Color.background.ignoresSafeArea()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home, system: "house")
            tabButton(.log, system: "doc.text")
            captureButton
            tabButton(.guide, system: "book")
            tabButton(.spots, system: "map")
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(tabBarBackground)
    }

    /// タブバーの帯。テーマ画像（tabbar）があればそれを横いっぱいに敷く
    private var tabBarBackground: some View {
        ZStack {
            DS.Color.surface
            if let image = ThemeAssets.image(.tabbar) {
                GeometryReader { geo in
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
    }

    private static func ornament(for tab: Tab) -> ThemeAssets.Name {
        switch tab {
        case .home: return .tabHome
        case .log: return .tabLog
        case .capture: return .tabCamera
        case .guide: return .tabGuide
        case .spots: return .tabSpots
        }
    }

    private func tabButton(_ tab: Tab, system: String) -> some View {
        Button {
            if selected == tab { NotificationCenter.default.post(name: .fogHomeReselected, object: tab == .home ? tab : nil) }
            selected = tab
        } label: {
            Group {
                if ThemeAssets.has(Self.ornament(for: tab)) {
                    // テーマのアイコン。選択中はテーマ色の丸い座布団と影で持ち上げ、他は少し薄く
                    ZStack {
                        if selected == tab {
                            Circle().fill(DS.Color.accent.opacity(0.22)).frame(width: 50, height: 50)
                        }
                        ThemeOrnament(name: Self.ornament(for: tab))
                            .frame(width: 40, height: 40)
                            .saturation(selected == tab ? 1 : 0.7)
                            .opacity(selected == tab ? 1 : 0.7)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                } else {
                    Image(systemName: selected == tab ? system + ".fill" : system)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(selected == tab ? DS.Color.textPrimary : DS.Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button { selected = .capture } label: {
            ZStack {
                if ThemeAssets.has(.tabCamera) {
                    // 明るいテーマはテーマ色の丸、暗いテーマは黒い丸にテーマ色の光（スライムが発光して見える）
                    Circle().fill(ThemeStore.shared.theme.isLight ? DS.Color.accent : DS.Color.surfaceRaised).frame(width: 58, height: 58)
                        .shadow(color: DS.Color.accent.opacity(ThemeStore.shared.theme.isLight ? 0.55 : 0.8), radius: 14)
                    ThemeOrnament(name: .tabCamera).frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                } else {
                    Circle().fill(DS.Color.accent).frame(width: 56, height: 56)
                        .shadow(color: DS.Color.accent.opacity(0.55), radius: 12)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撮影")
    }
}

extension Notification.Name {
    /// 表示中のタブをもう一度押したとき（ホームは今日に戻る）
    static let fogHomeReselected = Notification.Name("fog.tabReselected")
}
