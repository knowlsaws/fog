import SwiftUI
import UniformTypeIdentifiers
import Core

/// 設定（§8、ホーム右上の歯車）。6 項目の入口を 1 画面に収め、各項目は 1 画面の子ページで完結する。
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var tackleCount = 0
    @State private var rigCount = 0

    var body: some View {
        NavigationStack {
            List {
                row("タックル", system: "wrench.and.screwdriver", trailing: "\(tackleCount)・\(rigCount)") { TackleSettingsView() }
                row("データ", system: "icloud", trailing: cloudLabel) { DataSettingsView() }
                row("通知", system: "bell", trailing: notifyLabel) { NotificationSettingsView() }
                row("判定", system: "fish", trailing: CoreMLSpeciesClassifier.modelVersion) { JudgementSettingsView() }
                row("自動検出", system: "location", trailing: SessionDetectionService.sensitivity.label) { DetectionSettingsView() }
                row("情報源", system: "info.circle", trailing: "") { SourcesSettingsView() }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .background(DS.Color.background)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(DS.Color.textSecondary) }
                }
            }
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in reload() }
        }
        .preferredColorScheme(.dark)
        .tint(DS.Color.accent)
    }

    private func reload() {
        tackleCount = (try? services.store.tackles().count) ?? 0
        rigCount = (try? services.store.rigs().count) ?? 0
    }

    private var cloudLabel: String {
        switch services.persistence.mode {
        case .cloudKit: return "iCloud"
        case .local: return "ローカル"
        case .inMemory: return "一時"
        }
    }

    private var notifyLabel: String {
        let on = NotificationSettings.Kind.allCases.filter { NotificationSettings.isEnabled($0) }.count
        return "\(on)/\(NotificationSettings.Kind.allCases.count)"
    }

    private func row<D: View>(_ title: String, system: String, trailing: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: system).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.Color.accent).frame(width: 24)
                Text(title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text(trailing).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.vertical, DS.Spacing.s)
        }
        .listRowBackground(DS.Color.background)
        .listRowSeparatorTint(DS.Color.surfaceRaised)
    }
}

extension DetectionSettings.Sensitivity {
    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

// MARK: - 共通部品

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func settingsRow() -> some View {
        listRowBackground(DS.Color.background).listRowSeparatorTint(DS.Color.surfaceRaised)
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View { Text(text).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
}

// MARK: - タックル

struct TackleSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var tackles: [Tackle] = []
    @State private var rigs: [Rig] = []
    @State private var editingTackle: Tackle?
    @State private var editingRig: Rig?
    static let maxRigs = 10

    var body: some View {
        SettingsPage(title: "タックル") {
            List {
                Section {
                    ForEach(tackles) { t in
                        Button { editingTackle = t } label: {
                            HStack {
                                Text(t.kind == .spinning ? "スピニング" : "ベイト").font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.accent)
                                    .padding(.horizontal, DS.Spacing.s).padding(.vertical, 2)
                                    .background(DS.Color.accent.opacity(0.15), in: Capsule())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                                    Text([t.rod, t.reel, t.line].filter { !$0.isEmpty }.joined(separator: " / "))
                                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .settingsRow()
                    }
                    .onDelete { idx in idx.map { tackles[$0] }.forEach { try? services.store.deleteTackle(id: $0.id) }; reload() }
                    Button { editingTackle = Tackle(kind: tackles.contains { $0.kind == .spinning } ? .bait : .spinning, name: "") } label: {
                        Label("タックルを追加", systemImage: "plus").font(DS.Font.label).foregroundStyle(DS.Color.accent)
                    }
                    .settingsRow()
                } header: { SectionLabel(text: "タックル") }

                Section {
                    ForEach(rigs) { r in
                        Button { editingRig = r } label: {
                            HStack {
                                Text(r.displayName).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                                Spacer()
                                Text(r.hookSize.isEmpty ? "" : "#\(r.hookSize)").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                        .settingsRow()
                    }
                    .onDelete { idx in idx.map { rigs[$0] }.forEach { try? services.store.deleteRig(id: $0.id) }; reload() }
                    if rigs.count < Self.maxRigs {
                        Button { editingRig = Rig(sinkerGrams: 14, hookSize: "", worm: "", sortOrder: rigs.count) } label: {
                            Label("リグを追加", systemImage: "plus").font(DS.Font.label).foregroundStyle(DS.Color.accent)
                        }
                        .settingsRow()
                    }
                } header: { SectionLabel(text: "リグプリセット \(rigs.count)/\(Self.maxRigs)") }
            }
            .listStyle(.plain)
        }
        .onAppear(perform: reload)
        .sheet(item: $editingTackle) { t in TackleEditSheet(tackle: t) { reload() }.presentationDetents([.medium]) }
        .sheet(item: $editingRig) { r in RigEditSheet(rig: r) { reload() }.presentationDetents([.medium]) }
    }

    private func reload() {
        tackles = (try? services.store.tackles()) ?? []
        rigs = ((try? services.store.rigs()) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

private struct TackleEditSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State var tackle: Tackle
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("種別", selection: $tackle.kind) {
                    Text("スピニング").tag(TackleKind.spinning)
                    Text("ベイト").tag(TackleKind.bait)
                }
                .pickerStyle(.segmented).settingsRow()
                TextField("名前（例: 岸壁ロック）", text: $tackle.name).settingsRow()
                TextField("ロッド", text: $tackle.rod).settingsRow()
                TextField("リール", text: $tackle.reel).settingsRow()
                TextField("ライン", text: $tackle.line).settingsRow()
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle("タックル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var t = tackle
                        if t.name.isEmpty { t.name = t.kind == .spinning ? "スピニング" : "ベイト" }
                        try? services.store.upsert(t)
                        onSave(); dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct RigEditSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State var rig: Rig
    @State private var grams: String = ""
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("名前（空なら重さとワームから）", text: $rig.name).settingsRow()
                HStack {
                    TextField("シンカー", text: $grams).keyboardType(.decimalPad)
                    Text("g").foregroundStyle(DS.Color.textTertiary)
                }
                .settingsRow()
                TextField("フックサイズ（例: 1/0）", text: $rig.hookSize).settingsRow()
                TextField("ワーム", text: $rig.worm).settingsRow()
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .navigationTitle("リグ")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { grams = rig.sinkerGrams == rig.sinkerGrams.rounded() ? String(Int(rig.sinkerGrams)) : String(rig.sinkerGrams) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var r = rig
                        r.sinkerGrams = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? r.sinkerGrams
                        try? services.store.upsert(r)
                        onSave(); dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - データ

struct DataSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var shareItems: ShareItems?
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var zipProgress: Double?
    @State private var message: String?

    struct ShareItems: Identifiable { let id = UUID(); let urls: [URL] }

    var body: some View {
        SettingsPage(title: "データ") {
            List {
                Section {
                    HStack {
                        Circle().fill(services.persistence.mode == .cloudKit ? DS.Color.secondary : DS.Color.textTertiary).frame(width: 8, height: 8)
                        Text(cloudStatus).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    }
                    .settingsRow()
                    if let err = services.persistence.fallbackError {
                        Text(err.localizedDescription).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).settingsRow()
                    }
                } header: { SectionLabel(text: "iCloud 同期") }

                Section {
                    actionRow("CSV エクスポート", system: "tablecells") { run { ShareItems(urls: try services.dataManager.exportCSV()) } }
                    actionRow("JSON エクスポート", system: "doc.text") { run { ShareItems(urls: [try services.dataManager.exportJSON()]) } }
                    if let p = zipProgress {
                        HStack {
                            ProgressView(value: p).tint(DS.Color.accent)
                            Text("\(Int(p * 100))%").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                        .settingsRow()
                    } else {
                        actionRow("写真付き ZIP", system: "photo.on.rectangle") { exportZip() }
                    }
                    actionRow("JSON から復元", system: "square.and.arrow.down") { importing = true }
                } header: { SectionLabel(text: "エクスポート・復元") }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("全データ削除", systemImage: "trash").font(DS.Font.label)
                    }
                    .settingsRow()
                    if let message {
                        Text(message).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).settingsRow()
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $shareItems) { items in ShareSheet(urls: items.urls) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let n = try services.dataManager.importJSON(from: url)
                message = "\(n) 釣行を復元しました"
            } catch { message = "復元できませんでした: \(error.localizedDescription)" }
        }
        .confirmationDialog("すべての釣果・釣行・釣り場を削除します。元に戻せません。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("全データ削除", role: .destructive) {
                do { try services.dataManager.deleteAll(); message = "削除しました" } catch { message = error.localizedDescription }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var cloudStatus: String {
        switch services.persistence.mode {
        case .cloudKit: return "iCloud に同期中"
        case .local: return "この端末だけに保存（iCloud 利用不可）"
        case .inMemory: return "一時保存（再起動で消えます）"
        }
    }

    private func actionRow(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
        }
        .settingsRow()
    }

    private func run(_ make: () throws -> ShareItems) {
        do { shareItems = try make() } catch { message = error.localizedDescription }
    }

    private func exportZip() {
        zipProgress = 0
        Task {
            do {
                let url = try await services.dataManager.exportZipWithPhotos { p in Task { @MainActor in zipProgress = p } }
                shareItems = ShareItems(urls: [url])
            } catch { message = error.localizedDescription }
            zipProgress = nil
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 通知

struct NotificationSettingsView: View {
    @State private var enabled: [NotificationSettings.Kind: Bool] = [:]

    var body: some View {
        SettingsPage(title: "通知") {
            List {
                ForEach(NotificationSettings.Kind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { enabled[kind] ?? NotificationSettings.isEnabled(kind) },
                        set: { enabled[kind] = $0; NotificationSettings.setEnabled($0, for: kind) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                            Text(kind.detail).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                    .tint(DS.Color.accent)
                    .settingsRow()
                }
            }
            .listStyle(.plain)
        }
        .task { await SessionNotifications.requestAuthorization() }
    }
}

// MARK: - 判定

struct JudgementSettingsView: View {
    var body: some View {
        SettingsPage(title: "判定") {
            List {
                HStack {
                    Text("魚種判定モデル").font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Text(CoreMLSpeciesClassifier.modelVersion).font(DS.Font.number(16)).foregroundStyle(DS.Color.textSecondary)
                }
                .settingsRow()
                HStack {
                    Text("修正履歴").font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Text("\(CoreMLSpeciesClassifier.loadCorrections().correctionCount) 件").font(DS.Font.number(16)).foregroundStyle(DS.Color.textSecondary)
                }
                .settingsRow()
                Text("修正は候補の並び順に反映されます。判定の学習は写真を集めてから（scripts/train_classifier）。")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).settingsRow()
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - 自動検出

struct DetectionSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var sensitivity: DetectionSettings.Sensitivity = SessionDetectionService.sensitivity

    var body: some View {
        SettingsPage(title: "自動検出") {
            List {
                Picker("感度", selection: $sensitivity) {
                    ForEach(DetectionSettings.Sensitivity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .settingsRow()
                .onChange(of: sensitivity) { _, s in services.detection.applySensitivity(s) }

                let s = DetectionSettings.forSensitivity(sensitivity)
                detailRow("開始", "同じ場所に \(Int(s.dwellToStart / 60)) 分とどまる")
                detailRow("終了", "\(Int(s.awayDistanceM)) m 離れて \(Int(s.awayToEnd / 60)) 分、または車で \(Int(s.drivingToEnd / 60)) 分")
                detailRow("ランガン", "\(Int(s.runAndGunMaxGap / 60)) 分・\(Int(s.runAndGunMaxDistanceM / 1000)) km 以内は同じ釣行")
            }
            .listStyle(.plain)
        }
    }

    private func detailRow(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).frame(width: 64, alignment: .leading)
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }
        .settingsRow()
    }
}

// MARK: - 情報源

struct SourcesSettingsView: View {
    @State private var weatherAttribution: (serviceName: String, legalURL: URL)?

    var body: some View {
        SettingsPage(title: "情報源") {
            List {
                Section {
                    Link(destination: EnvironmentService.openMeteoCredit.url) {
                        HStack {
                            Text(EnvironmentService.openMeteoCredit.text).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                    .settingsRow()
                    if let a = weatherAttribution {
                        Link(destination: a.legalURL) {
                            HStack {
                                Text(a.serviceName).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                        .settingsRow()
                    }
                    Text("潮汐: 気象庁 潮位表（分潮）").font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).settingsRow()
                } header: { SectionLabel(text: "海況・潮汐") }
                Section {
                    Text("RSS の登録は F-27（L17）で追加します。").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).settingsRow()
                } header: { SectionLabel(text: "釣果情報") }
            }
            .listStyle(.plain)
        }
        .task { weatherAttribution = await WeatherKitProvider.attribution() }
    }
}
