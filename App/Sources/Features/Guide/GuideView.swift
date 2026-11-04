import SwiftUI
import Core

/// プレースホルダー（L0）。実装は docs/03_loop_plan.md の該当ループで行う。
struct GuideView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Guide")
                .font(DS.Font.number(28))
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
