import Foundation

// 純粋な値型（Codable）。SwiftData の @Model は App 側で、これらと相互変換する（L1）。

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Spot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var coordinate: Coordinate
    public var isRegistered: Bool
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, coordinate: Coordinate, isRegistered: Bool = true, createdAt: Date = .now) {
        self.id = id; self.name = name; self.coordinate = coordinate; self.isRegistered = isRegistered; self.createdAt = createdAt
    }
}

public enum TackleKind: String, Codable, Sendable { case spinning, bait }

public struct Rig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sinkerGrams: Double
    public var hookSize: String
    public var worm: String
    public init(id: UUID = UUID(), sinkerGrams: Double, hookSize: String, worm: String) {
        self.id = id; self.sinkerGrams = sinkerGrams; self.hookSize = hookSize; self.worm = worm
    }
}

public struct EnvSnapshot: Codable, Hashable, Sendable {
    public var at: Date
    public var coordinate: Coordinate
    public var airTemperatureC: Double?
    public var windSpeedMS: Double?
    public var windGustMS: Double?
    public var windDirectionDeg: Double?
    public var pressureHPa: Double?
    public var pressureTrend3hHPa: Double?
    public var cloudCover: Double?
    public var precipitationMM: Double?
    public var tideLevelCm: Double?
    public var tideRateCmPerHour: Double?
    public var tideName: String?
    public var waveHeightM: Double?
    public var wavePeriodS: Double?
    public var seaSurfaceTempC: Double?
    public var moonAge: Double?
    public var isForecast: Bool
    public init(at: Date, coordinate: Coordinate, isForecast: Bool = false) {
        self.at = at; self.coordinate = coordinate; self.isForecast = isForecast
    }
}

public struct Catch: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var at: Date
    public var coordinate: Coordinate
    public var species: String
    public var speciesConfidence: Double
    public var lengthCm: Double?
    public var lengthErrorCm: Double?
    public var photoLocalIdentifier: String?
    public var tackle: TackleKind?
    public var rigID: UUID?
    public var env: EnvSnapshot?
    public var released: Bool
    public init(id: UUID = UUID(), sessionID: UUID, at: Date, coordinate: Coordinate, species: String, speciesConfidence: Double, lengthCm: Double? = nil, lengthErrorCm: Double? = nil, photoLocalIdentifier: String? = nil, tackle: TackleKind? = nil, rigID: UUID? = nil, env: EnvSnapshot? = nil, released: Bool = true) {
        self.id = id; self.sessionID = sessionID; self.at = at; self.coordinate = coordinate; self.species = species
        self.speciesConfidence = speciesConfidence; self.lengthCm = lengthCm; self.lengthErrorCm = lengthErrorCm
        self.photoLocalIdentifier = photoLocalIdentifier; self.tackle = tackle; self.rigID = rigID; self.env = env; self.released = released
    }
}

public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var spotID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var snapshots: [EnvSnapshot]
    public var catches: [Catch]
    public var tackle: TackleKind?
    public var rigID: UUID?
    public init(id: UUID = UUID(), spotID: UUID, startedAt: Date, endedAt: Date? = nil, snapshots: [EnvSnapshot] = [], catches: [Catch] = [], tackle: TackleKind? = nil, rigID: UUID? = nil) {
        self.id = id; self.spotID = spotID; self.startedAt = startedAt; self.endedAt = endedAt
        self.snapshots = snapshots; self.catches = catches; self.tackle = tackle; self.rigID = rigID
    }
    public var isBlank: Bool { catches.isEmpty }
}
