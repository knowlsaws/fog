import Foundation

/// Open-Meteo Marine は海上格子のため、漁港内や湾奥の座標は値が返らない。
/// 周囲を近い順に探索して最初に値が返る格子点を使う（釣り場ごとにキャッシュ）。
public enum MarineGridSearch {
    /// 中心から近い順の候補（中心 → 8 方位 × 距離 3 段階、約 2.5 / 5 / 10 km）。
    public static func candidates(around c: Coordinate) -> [Coordinate] {
        var out = [c]
        let steps: [Double] = [0.025, 0.05, 0.1]
        let latScale = 1.0
        let lonScale = 1.0 / max(0.2, cos(Angle.rad(c.latitude)))
        for d in steps {
            for (dy, dx) in [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                out.append(Coordinate(latitude: c.latitude + Double(dy) * d * latScale,
                                      longitude: c.longitude + Double(dx) * d * lonScale))
            }
        }
        return out
    }

    /// `probe` が nil（陸扱い）を返す間は次の候補へ。見つかれば (格子点, 結果)。
    public static func find<T>(around c: Coordinate, maxAttempts: Int = 12, probe: (Coordinate) async throws -> T?) async rethrows -> (Coordinate, T)? {
        for candidate in candidates(around: c).prefix(maxAttempts) {
            if let value = try await probe(candidate) { return (candidate, value) }
        }
        return nil
    }
}
