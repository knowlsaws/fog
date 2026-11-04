import Foundation
import CoreGraphics
import UIKit
import Core
import os

/// 撮影 1 回を釣果 1 尾にする（§4）。時刻・位置・セッション・ポイント・タックル・リグ・環境を自動で付け、
/// 連続撮影は同一個体にまとめ、写真はライブラリに保存してアプリにはサムネイルだけ持つ。
@MainActor
@Observable
final class CaptureService {
    struct Outcome: Sendable {
        var catchRecord: Catch
        var merged: Bool
        var record: Analytics.RecordJudgement?
    }

    private let store: FogStore
    private let environment: EnvironmentService
    private let detection: SessionDetectionService
    private let classifier: SpeciesClassifying
    private let library = PhotoLibraryService()
    private static let log = Logger(subsystem: "fog", category: "capture")

    /// 撮影画面の例外的入力（タックル・リグ）。次回へ引き継ぐ（F-14）
    /// App Group に置き、ウィジェットのタックル切替と同じ値を見る（F-14）。
    var currentTackle: TackleKind? {
        get { FogShared.currentTackle }
        set { FogShared.currentTackle = newValue; WidgetSync.setTackle(newValue) }
    }
    var currentRigID: UUID? {
        get { UserDefaults.standard.string(forKey: "fog.currentRig").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "fog.currentRig") }
    }

    init(store: FogStore, environment: EnvironmentService, detection: SessionDetectionService, classifier: SpeciesClassifying = CoreMLSpeciesClassifier()) {
        self.store = store
        self.environment = environment
        self.detection = detection
        self.classifier = classifier
    }

    /// シャッター：画像（縦向き）と計測結果から釣果を保存する。2 秒以内に返す（写真保存は非同期で続ける）。
    func record(jpeg: Data, image: CGImage, measurement: LengthMeasurement?, at date: Date = .now, coordinate: Coordinate?) async -> Outcome? {
        let candidates = await classifier.classify(image)
        let session = await ensureSession(at: date, coordinate: coordinate)
        let location = coordinate ?? (try? store.spot(id: session.spotID))?.coordinate ?? Coordinate(latitude: 0, longitude: 0)
        var item = Catch(
            sessionID: session.id, at: date, coordinate: location,
            species: candidates.first?.species ?? "", speciesConfidence: candidates.first?.confidence ?? 0,
            lengthCm: measurement?.lengthCm, lengthErrorCm: measurement?.errorCm,
            tackle: currentTackle ?? session.tackle, rigID: currentRigID ?? session.rigID,
            env: environment.snapshot(at: date, coordinate: location),
            pointID: detection.currentPointID(), speciesCandidates: candidates, tackleID: session.tackleID
        )
        // 写真をライブラリへ（失敗しても釣果は残す）
        if let identifier = try? await library.save(jpeg: jpeg, at: date, coordinate: coordinate) {
            item.photoLocalIdentifier = identifier
            item.photoLocalIdentifiers = [identifier]
        }
        return persist(item, in: session, thumbnail: PhotoLibraryService.thumbnailJPEG(from: image))
    }

    /// 取り込み（標準カメラの写真）：サイズ未計測で保存。
    func recordImported(image: CGImage, photoIdentifier: String, at date: Date, coordinate: Coordinate?, session: Core.Session) async -> Outcome? {
        let candidates = await classifier.classify(image)
        let location = coordinate ?? (try? store.spot(id: session.spotID))?.coordinate ?? Coordinate(latitude: 0, longitude: 0)
        let item = Catch(
            sessionID: session.id, at: date, coordinate: location,
            species: candidates.first?.species ?? "", speciesConfidence: candidates.first?.confidence ?? 0,
            photoLocalIdentifier: photoIdentifier, tackle: session.tackle, rigID: session.rigID,
            env: environment.snapshot(at: date, coordinate: location),
            speciesCandidates: candidates, photoLocalIdentifiers: [photoIdentifier], tackleID: session.tackleID
        )
        return persist(item, in: session, thumbnail: PhotoLibraryService.thumbnailJPEG(from: image))
    }

    private func persist(_ item: Catch, in session: Core.Session, thumbnail: Data?) -> Outcome? {
        guard var current = try? store.session(id: session.id) else { return nil }
        var merged = false
        var saved = item
        if let same = CatchMerger.findSameIndividual(for: item, in: current.catches) {
            saved = CatchMerger.merge(base: same, new: item)
            current.catches = current.catches.map { $0.id == same.id ? saved : $0 }
            merged = true
        } else {
            current.catches.append(saved)
        }
        do {
            try store.upsert(current)
            if let thumbnail, !merged || saved.photoLocalIdentifier == item.photoLocalIdentifier {
                try store.setThumbnail(catchID: saved.id, jpeg: thumbnail)
            }
        } catch {
            Self.log.error("catch save failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let record = merged ? nil : judge(saved, spotID: current.spotID)
        // 記録更新の通知はアプリを閉じているときだけ（撮影直後はシートで見せる。§8）
        if let record, record.hasAny, UIApplication.shared.applicationState != .active {
            SessionNotifications.record(species: saved.species, lengthCm: saved.lengthCm, judgement: record)
        }
        return Outcome(catchRecord: saved, merged: merged, record: record)
    }

    private func judge(_ new: Catch, spotID: UUID) -> Analytics.RecordJudgement {
        let all = (try? store.sessions()) ?? []
        let existing = all.flatMap { s in s.catches.map { ($0, s.spotID) } }
        return Analytics.judge(new: new, newSpotID: spotID, existing: existing)
    }

    /// 記録中の釣行。無ければ撮影位置で手動の釣行を始める（撮影は釣行の証拠）。
    private func ensureSession(at date: Date, coordinate: Coordinate?) async -> Core.Session {
        if let active = try? store.activeSession() { return active }
        let location = coordinate ?? Coordinate(latitude: 0, longitude: 0)
        let spots = (try? store.spots()) ?? []
        let near = spots.filter(\.isRegistered).min { Geo.distanceMeters($0.coordinate, location) < Geo.distanceMeters($1.coordinate, location) }
        let spot: Spot
        if let near, Geo.distanceMeters(near.coordinate, location) <= SessionDetectionService.registeredSpotRadiusM {
            spot = near
        } else {
            spot = Spot(name: "釣り場", coordinate: location, isRegistered: true, createdAt: date)
            try? store.upsert(spot)
        }
        let previous = (try? store.sessions())?.first
        let session = Core.Session(spotID: spot.id, startedAt: date, tackle: previous?.tackle, rigID: previous?.rigID,
                                   track: [TrackSample(at: date, coordinate: location)], tackleID: previous?.tackleID, isAutoDetected: false)
        try? store.upsert(session)
        return session
    }

    /// 釣果の削除。写真は求められたときだけライブラリからも消す（削除は分析に即時反映）。
    func deleteCatch(id: UUID, deletePhoto: Bool) async {
        let item = (try? store.catches())?.first { $0.id == id }
        try? store.deleteCatch(id: id)
        if deletePhoto, let item {
            await PhotoLibraryService.delete(identifiers: [item.photoLocalIdentifier].compactMap { $0 } + item.photoLocalIdentifiers)
        }
    }

    /// サイズの手入力・修正（F-12/F-24）。手入力は推定幅 0.5 cm とする。
    func setLength(catchID: UUID, lengthCm: Double?) {
        guard let all = try? store.sessions(), var session = all.first(where: { $0.catches.contains { $0.id == catchID } }),
              let index = session.catches.firstIndex(where: { $0.id == catchID }) else { return }
        session.catches[index].lengthCm = lengthCm
        session.catches[index].lengthErrorCm = lengthCm == nil ? nil : 0.5
        try? store.upsert(session)
    }

    /// 魚種の確定（候補 3 種の 1 タップ、F-10）／後からの修正（F-24）。
    func setSpecies(catchID: UUID, species: String, corrected: Bool) {
        guard let all = try? store.sessions(), var session = all.first(where: { $0.catches.contains { $0.id == catchID } }),
              let index = session.catches.firstIndex(where: { $0.id == catchID }) else { return }
        let predicted = session.catches[index].speciesCandidates.first?.species ?? session.catches[index].species
        session.catches[index].species = species
        session.catches[index].speciesCorrected = corrected
        if corrected { session.catches[index].speciesConfidence = 1 }
        try? store.upsert(session)
        // 端末内の補正テーブルに学習（次回の候補順に反映。F-24）
        CoreMLSpeciesClassifier.learn(predicted: predicted, corrected: species)
    }
}
