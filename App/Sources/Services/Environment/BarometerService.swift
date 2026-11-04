import Foundation
import CoreMotion
import Core

/// 端末の気圧計（CMAltimeter）。釣行中は連続で取り、直近 6 時間を保持して 3 時間傾向を出す。
@MainActor
@Observable
final class BarometerService {
    private(set) var samples: [PressureSample] = []
    private(set) var isRunning = false
    private let altimeter = CMAltimeter()
    private let queue = OperationQueue()

    static var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    init() {
        queue.name = "fog.barometer"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard !isRunning, Self.isAvailable else { return }
        isRunning = true
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let data else { return }
            let hPa = data.pressure.doubleValue * 10 // kPa → hPa
            Task { @MainActor in self?.append(PressureSample(at: Date(), pressureHPa: hPa)) }
        }
    }

    func stop() {
        guard isRunning else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }

    func append(_ sample: PressureSample) {
        // 1 分に 1 点に間引く
        if let last = samples.last, sample.at.timeIntervalSince(last.at) < 60 { return }
        samples = PressureTrend.prune(samples + [sample], now: sample.at)
    }

    var latest: PressureSample? { samples.last }
    func trend3h(now: Date = .now) -> Double? { PressureTrend.threeHourChange(samples, now: now) }
}
