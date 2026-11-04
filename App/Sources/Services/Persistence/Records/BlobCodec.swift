import Foundation
import Core

/// SwiftData のレコードに Core の値型を JSON で埋め込むための補助。
/// 配列や入れ子（候補3種、軌跡、釣果時の環境など）は独立したテーブルにせず、Core の Codable をそのまま使う。
/// CloudKit は配列属性に制約があるため `Data?` で持つ。
enum BlobCodec {
    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? FogJSON.encode(value, pretty: false)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? FogJSON.decode(type, from: data)
    }
}
