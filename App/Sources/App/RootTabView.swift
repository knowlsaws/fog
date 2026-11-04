import SwiftUI

/// 5タブ。文字ラベルなし、中央は撮影（オレンジの円）。
/// L0 ではプレースホルダー。各画面は Features/ 配下のループで実装する。
struct RootTabView: View {
    enum Tab: Hashable { case home, log, capture, guide, spots }
    @State private var selected: Tab = .home
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .background(DS.Color.background)
            .environment(\.captureTab, { selected = .capture })

            tabBar
        }
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
        .padding(.top, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.m)
        .background(
            DS.Color.surface
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: Tab, system: String) -> some View {
        Button { selected = tab } label: {
            Image(systemName: selected == tab ? system + ".fill" : system)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(selected == tab ? DS.Color.textPrimary : DS.Color.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button { selected = .capture } label: {
            ZStack {
                Circle().fill(DS.Color.accent).frame(width: 64, height: 64)
                    .shadow(color: DS.Color.accent.opacity(0.55), radius: 14)
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撮影")
    }
}

