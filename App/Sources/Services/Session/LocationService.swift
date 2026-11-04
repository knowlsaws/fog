import Foundation
import CoreLocation
import Core

/// CoreLocation の薄いラッパ。待機中は省電力（Visits ＋ 大きな移動）、釣行中は低頻度の標準更新。
/// バックグラウンドで動く（Info.plist の location バックグラウンドモード、常に許可）。
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Mode { case off, monitoring, tracking }

    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus
    private(set) var mode: Mode = .off
    private(set) var lastFix: LocationFix?
    private var continuations: [UUID: AsyncStream<LocationFix>.Continuation] = [:]

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        manager.activityType = .otherNavigation
    }

    /// 位置の流れ。複数の購読者が同じ fix を受け取る。
    func fixes() -> AsyncStream<LocationFix> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// 待機：Visits と大きな移動で起こされる（省電力）。
    func startMonitoring() {
        guard mode != .monitoring else { return }
        manager.stopUpdatingLocation()
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
        mode = .monitoring
    }

    /// 釣行中：100 m 精度・25 m 間隔の低頻度更新。
    func startTracking() {
        guard mode != .tracking else { return }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        manager.startUpdatingLocation()
        mode = .tracking
    }

    /// 滞在判定のため、待機中でも一時的に通常更新を回す（数分で `startMonitoring` に戻す）。
    func probe() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        mode = .off
    }

    private func publish(_ fix: LocationFix) {
        lastFix = fix
        for c in continuations.values { c.yield(fix) }
    }

    // MARK: CLLocationManagerDelegate（nonisolated → MainActor へ）

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { l in
            LocationFix(at: l.timestamp, coordinate: Coordinate(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude),
                        horizontalAccuracyM: l.horizontalAccuracy, speedMS: l.speed >= 0 ? l.speed : nil)
        }
        Task { @MainActor in for f in fixes { self.publish(f) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // 到着した Visit は滞在の有力な手がかり。到着時刻を速度 0 の fix として流す
        let fix = LocationFix(at: visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate,
                              coordinate: Coordinate(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude),
                              horizontalAccuracyM: visit.horizontalAccuracy, speedMS: 0)
        Task { @MainActor in
            self.publish(fix)
            self.probe()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
