import Foundation
import Core

/// 海況の取得元。テストではモックに差し替える。
protocol MarineProviding: Sendable {
    /// 値が返る最初の海上格子点と、その 1 時間値。全候補が陸なら nil。
    func fetch(around coordinate: Coordinate) async throws -> (grid: Coordinate, samples: [MarineSample])?
}

/// Open-Meteo Marine API（無料・キー不要・CC BY 4.0）。漁港内の座標は陸扱いになるので周囲を探索する。
struct OpenMeteoMarineClient: MarineProviding {
    var session: URLSession = .shared

    enum ClientError: LocalizedError {
        case http(Int)
        case api(String)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Open-Meteo HTTP \(code)"
            case .api(let reason): return "Open-Meteo: \(reason)"
            }
        }
    }

    func fetch(around coordinate: Coordinate) async throws -> (grid: Coordinate, samples: [MarineSample])? {
        try await MarineGridSearch.find(around: coordinate) { candidate -> [MarineSample]? in
            try await probe(candidate)
        }.map { (grid: $0.0, samples: $0.1) }
    }

    /// 陸なら nil。
    func probe(_ c: Coordinate) async throws -> [MarineSample]? {
        var request = URLRequest(url: OpenMeteoMarine.url(for: c))
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), http.statusCode != 400 {
            throw ClientError.http(http.statusCode)
        }
        switch OpenMeteoMarine.decode(data) {
        case .samples(let s): return s
        case .land: return nil
        case .error(let reason):
            // 海上でない座標には 400 + error を返すことがある → 陸扱いで次の候補へ
            if reason.localizedCaseInsensitiveContains("coordinate") || reason.localizedCaseInsensitiveContains("sea") { return nil }
            throw ClientError.api(reason)
        }
    }
}
