import Foundation
import CoreMotion
import Core

/// 釣行中の歩数・歩行距離（CoreMotion の CMPedometer）。HealthKit は使わない（権限と設定が増えるだけで同じ値が取れる）。
struct PedometerService {
    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func activity(from: Date, to: Date) async -> ActivitySummary? {
        guard Self.isAvailable else { return nil }
        let pedometer = CMPedometer()
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                guard let data else { return cont.resume(returning: nil) }
                cont.resume(returning: ActivitySummary(stepCount: data.numberOfSteps.intValue, walkingDistanceM: data.distance?.doubleValue))
            }
        }
    }
}
