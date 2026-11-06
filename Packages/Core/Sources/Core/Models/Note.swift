import Foundation

/// 地図に置くメモ（F-52）。店先で聞いた話など、場所に紐づく自由記述。手入力か、音声から整理したもの。
public struct Note: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case manual, voice }
    public var id: UUID
    public var coordinate: Coordinate
    public var text: String
    /// 場所の名前（漁港名など）。無くてよい
    public var placeName: String?
    public var source: Source
    public var createdAt: Date

    public init(id: UUID = UUID(), coordinate: Coordinate, text: String, placeName: String? = nil, source: Source = .manual, createdAt: Date = .now) {
        self.id = id
        self.coordinate = coordinate
        self.text = text
        self.placeName = placeName
        self.source = source
        self.createdAt = createdAt
    }
}
