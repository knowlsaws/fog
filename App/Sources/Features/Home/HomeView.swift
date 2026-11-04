import SwiftUI
import Core

/// プレースホルダー（L0）。実装は docs/03_loop_plan.md の該当ループで行う。
struct HomeView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Home")
                .font(DS.Font.number(28))
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
