import SwiftUI
import SwiftData
import Core

/// プレースホルダー（L0）。L11 で実装。
/// L1 では保存された釣行をそのまま並べ、ストアが再起動後も残ることを実機で確認できるようにしている。
struct LogView: View {
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var sessions: [SessionRecord]

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            Spacer()
            Text("\(sessions.count)")
                .font(DS.Font.score(72))
                .foregroundStyle(DS.Color.textPrimary)
            Text("釣行")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textTertiary)
            VStack(spacing: DS.Spacing.s) {
                ForEach(sessions.prefix(5)) { session in
                    row(session)
                }
            }
            .padding(.top, DS.Spacing.l)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.xl)
    }

    private func row(_ session: SessionRecord) -> some View {
        let catchCount = session.catches?.count ?? 0
        return HStack(spacing: DS.Spacing.m) {
            Text(session.startedAt, format: .dateTime.month().day())
                .font(DS.Font.number(15))
                .foregroundStyle(DS.Color.textSecondary)
            Text(session.spot?.name ?? "—")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer()
            Text(catchCount == 0 ? "ボウズ" : "\(catchCount)尾")
                .font(DS.Font.number(15))
                .foregroundStyle(catchCount == 0 ? DS.Color.textTertiary : DS.Color.accent)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
    }
}

#Preview {
    let persistence = PersistenceController.inMemory()
    let store = FogStore(container: persistence.container)
    SampleSeeder.seedIfNeeded(store: store)
    return LogView()
        .background(DS.Color.background)
        .modelContainer(persistence.container)
        .environment(store)
}
