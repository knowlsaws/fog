import SwiftUI
import ARKit
import Core

/// 撮影（§5）。全画面カメラ、中央の計測枠、タックル／リグのチップ、シャッター、結果シート。L10 で仕上げる。
struct CaptureView: View {
    @Environment(AppServices.self) private var services
    @State private var model = CaptureViewModel()
    @State private var showRigPicker = false

    var body: some View {
        ZStack {
            if DepthCaptureSession.isSupported {
                ARPreview(session: model.depth.session).ignoresSafeArea()
            } else {
                DS.Color.background.ignoresSafeArea()
                Text("LiDAR 非対応").font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
            }
            MeasureFrame(status: model.status, lengthCm: model.liveLengthCm, endpoints: model.endpoints)
            VStack {
                header
                Spacer()
                controls
            }
            if let result = model.result {
                ResultSheet(outcome: result, onChoose: { model.choose(species: $0) }, onDismiss: { model.dismissResult() })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.result?.catchRecord.id)
        .onAppear { model.attach(services: services); model.start() }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showRigPicker) { rigPicker }
    }

    private var header: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text(model.spotName.isEmpty ? "—" : model.spotName).font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                Text(Date.now, format: .dateTime.hour().minute()).font(DS.Font.number(13)).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
        }
        .padding(.top, DS.Spacing.m)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            chip(model.tackle == .spinning ? "スピニング" : "ベイト") { model.toggleTackle() }
            Spacer()
            Button {
                Task { await model.shutter() }
            } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.6), lineWidth: 3).frame(width: 84, height: 84)
                    Circle().fill(DS.Color.accent).frame(width: 70, height: 70)
                        .opacity(model.isSaving ? 0.5 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving)
            .accessibilityLabel("撮影")
            Spacer()
            chip(model.rig?.displayName ?? "リグ") { showRigPicker = true }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.bottom, 96)
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.s)
                .background(DS.Color.surface.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: 110)
    }

    private var rigPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if model.rigs.isEmpty {
                Text("設定でリグを登録すると選べます").font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
            }
            ForEach(model.rigs) { r in
                Button { model.selectRig(r); showRigPicker = false } label: {
                    HStack {
                        Text(r.displayName).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        if model.rig?.id == r.id { Circle().fill(DS.Color.accent).frame(width: 8, height: 8) }
                    }
                    .padding(DS.Spacing.m)
                    .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
        .presentationDetents([.medium])
    }
}

/// ARKit のカメラ映像（ARSCNView の背景だけを使う）。
struct ARPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersContinuously = true
        view.scene = SCNScene()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// 計測枠：魚を捉えると枠がオレンジになり、全長をライブ表示。遠い・近いはグレーで矢印。
struct MeasureFrame: View {
    let status: FrameStatus
    let lengthCm: Double?
    let endpoints: (CGPoint, CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.86, h = geo.size.height * 0.26
            let color: Color = status == .ok ? DS.Color.accent : DS.Color.faded
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(color, lineWidth: status == .ok ? 3 : 2)
                    .frame(width: w, height: h)
                if let (a, b) = endpoints, status == .ok {
                    Path { p in
                        p.move(to: CGPoint(x: a.x * geo.size.width, y: a.y * geo.size.height))
                        p.addLine(to: CGPoint(x: b.x * geo.size.width, y: b.y * geo.size.height))
                    }
                    .stroke(DS.Color.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                VStack {
                    Spacer()
                    if let lengthCm, status == .ok {
                        Text("\(Int(lengthCm.rounded()))cm")
                            .font(DS.Font.score(44))
                            .foregroundStyle(DS.Color.accent)
                            .shadow(radius: 6)
                    } else if status == .tooFar {
                        Image(systemName: "arrow.down").font(.system(size: 32, weight: .bold)).foregroundStyle(DS.Color.faded)
                    } else if status == .tooClose {
                        Image(systemName: "arrow.up").font(.system(size: 32, weight: .bold)).foregroundStyle(DS.Color.faded)
                    }
                    Spacer().frame(height: geo.size.height * 0.32)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// 撮影後の結果シート：魚種名、全長、確信度の円弧。記録更新ならオレンジのバッジ。低確信度なら候補 3 種。
struct ResultSheet: View {
    let outcome: CaptureService.Outcome
    let onChoose: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: DS.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                    Text(outcome.catchRecord.species.isEmpty ? "判定中" : outcome.catchRecord.species)
                        .font(DS.Font.number(24)).foregroundStyle(DS.Color.textPrimary)
                    if let l = outcome.catchRecord.lengthCm {
                        Text("\(Int(l.rounded()))cm").font(DS.Font.score(40)).foregroundStyle(DS.Color.accent)
                        if let e = outcome.catchRecord.lengthErrorCm {
                            Text("±\(Int(e.rounded()))").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                        }
                    } else {
                        Text("サイズ未計測").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                    Spacer()
                    ZStack {
                        Circle().stroke(DS.Color.faded, lineWidth: 4)
                        Circle().trim(from: 0, to: CGFloat(outcome.catchRecord.speciesConfidence))
                            .stroke(DS.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 32, height: 32)
                }
                if let record = outcome.record, record.hasAny {
                    HStack(spacing: DS.Spacing.s) {
                        if record.isFirstSpecies { badge("初") }
                        if record.isPersonalBest { badge("自己記録") }
                        if record.isSpotRecord && !record.isPersonalBest { badge("釣り場記録") }
                        Spacer()
                    }
                }
                if outcome.merged {
                    Text("同じ魚にまとめました").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                if outcome.catchRecord.speciesConfidence < 0.7 && outcome.catchRecord.speciesCandidates.count > 1 {
                    HStack(spacing: DS.Spacing.s) {
                        ForEach(outcome.catchRecord.speciesCandidates.prefix(3), id: \.species) { c in
                            Button { onChoose(c.species) } label: {
                                Text(c.species)
                                    .font(DS.Font.label)
                                    .foregroundStyle(c.species == outcome.catchRecord.species ? DS.Color.background : DS.Color.textPrimary)
                                    .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.s)
                                    .background(c.species == outcome.catchRecord.species ? DS.Color.accent.opacity(0.9) : DS.Color.surfaceRaised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(DS.Spacing.l)
            .background(DS.Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, 190)
            .onTapGesture { onDismiss() }
            .task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                onDismiss()
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(DS.Font.label).foregroundStyle(DS.Color.background)
            .padding(.horizontal, DS.Spacing.s).padding(.vertical, 3)
            .background(DS.Color.accent, in: Capsule())
    }
}
