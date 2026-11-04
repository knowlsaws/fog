import Foundation
import SwiftUI
import AVFoundation
import Core

/// 撮影画面の状態。ARKit のフレームを間引いて輪郭・全長をライブ計算し、シャッターで釣果にする。
@MainActor
@Observable
final class CaptureViewModel {
    let depth = DepthCaptureSession()
    private let segmenter = FishSegmenter()
    private var capture: CaptureService?
    private var store: FogStore?
    private var location: LocationService?

    private(set) var status: FrameStatus = .searching
    private(set) var liveLengthCm: Double?
    private(set) var liveMeasurement: LengthMeasurement?
    private(set) var endpoints: (CGPoint, CGPoint)?
    private(set) var result: CaptureService.Outcome?
    private(set) var isSaving = false
    private(set) var spotName: String = ""
    private(set) var torchOn = false
    var tackle: TackleKind = .spinning
    var rig: Rig?
    var rigs: [Rig] = []
    private var frameCounter = 0
    private var analyzing = false
    private var lastResultAt: Date?

    func attach(services: AppServices) {
        store = services.store
        location = services.location
        // 撮影位置を付けるため、画面を開いたら位置を取り始める（釣行の記録中でなくても）
        if (try? services.store.activeSession()) == nil { services.location.probe() }
        if capture == nil { capture = services.capture }
        tackle = services.capture.currentTackle ?? ((try? services.store.sessions())?.first?.tackle) ?? .spinning
        rigs = (try? services.store.rigs()) ?? []
        rig = rigs.first { $0.id == services.capture.currentRigID } ?? rigs.first
        spotName = services.detection.activeSpotName ?? ""
    }

    func start() {
        depth.onFrame = { [weak self] frame in self?.handle(frame) }
        depth.start()
    }

    func stop() {
        depth.pause()
        depth.onFrame = nil
    }

    private func handle(_ frame: DepthCaptureSession.Frame) {
        frameCounter += 1
        guard frameCounter % 6 == 0, !analyzing else { return }
        analyzing = true
        let segmenter = self.segmenter
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = segmenter.analyze(frame)
            await MainActor.run {
                guard let self else { return }
                self.analyzing = false
                self.status = r.status
                self.liveMeasurement = r.measurement
                self.liveLengthCm = r.status == .ok ? r.measurement?.lengthCm : nil
                if let (a, b) = r.endpoints {
                    // 縦向き表示：撮影画像は横向きなので (x, y) → (height − y, x) に回す
                    let w = Double(frame.imageSize.width), h = Double(frame.imageSize.height)
                    self.endpoints = (CGPoint(x: (h - a.y) / h, y: a.x / w), CGPoint(x: (h - b.y) / h, y: b.x / w))
                } else {
                    self.endpoints = nil
                }
            }
        }
    }

    /// シャッター。保存まで 2 秒以内（写真保存を待たずに結果を返す設計は CaptureService 側）。
    func shutter() async {
        guard !isSaving, let capture, let frame = depth.latest else { return }
        isSaving = true
        defer { isSaving = false }
        guard let (jpeg, image) = CaptureImageConverter.jpegAndImage(from: frame.image) else { return }
        let measurement = status == .ok ? liveMeasurement : nil
        capture.currentTackle = tackle
        capture.currentRigID = rig?.id
        let coordinate = depthCoordinate()
        result = await capture.record(jpeg: jpeg, image: image, measurement: measurement, coordinate: coordinate)
        lastResultAt = .now
    }

    /// 撮影位置：記録中の釣行の最後の立ち位置 → 端末の最新の位置（撮影画面を開いたときに取り始める）
    private func depthCoordinate() -> Coordinate? {
        if let store, let active = try? store.activeSession(), let c = active.track.last?.coordinate, c.isPlausible { return c }
        if let c = location?.lastFix?.coordinate, c.isPlausible { return c }
        return nil
    }

    func dismissResult() { result = nil }

    /// 夜のライト（LiDAR は暗くても測れるが、輪郭検出には光が要る）。
    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            device.unlockForConfiguration()
            torchOn.toggle()
        } catch {}
    }

    func choose(species: String) {
        guard let result, let capture else { return }
        capture.setSpecies(catchID: result.catchRecord.id, species: species, corrected: false)
        var updated = result
        updated.catchRecord.species = species
        self.result = updated
    }

    func toggleTackle() {
        tackle = tackle == .spinning ? .bait : .spinning
        capture?.currentTackle = tackle
    }

    func selectRig(_ r: Rig) {
        rig = r
        capture?.currentRigID = r.id
    }
}
