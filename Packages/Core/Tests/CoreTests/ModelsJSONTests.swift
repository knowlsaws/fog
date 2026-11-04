import Foundation
import XCTest
@testable import Core

/// L1 受け入れ条件: Core のモデルに JSON の往復テスト。
/// 9つの値型（Session, Catch, Spot, Point, EnvSnapshot, Tackle, Rig, HookEvent, Species）それぞれと、
/// チェックインしたフィクスチャ（スキーマが読めなくなっていないか）を確認する。
final class ModelsJSONTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try FogJSON.encode(value)
        let decoded = try FogJSON.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
        // 2回目も同じバイト列（キーがソートされ、日付表現が安定している）
        XCTAssertEqual(try FogJSON.encode(decoded), data, file: file, line: line)
    }

    func testSpotRoundTrip() throws { try roundTrip(SampleData.spot()) }
    func testPointRoundTrip() throws { try roundTrip(SampleData.point()) }
    func testTackleRoundTrip() throws { try roundTrip(SampleData.tackle()) }
    func testRigRoundTrip() throws { try roundTrip(SampleData.rig()) }
    func testHookEventRoundTrip() throws { try roundTrip(SampleData.hookEvent()) }
    func testCatchRoundTrip() throws { try roundTrip(SampleData.catchRecord()) }
    func testSessionRoundTrip() throws { try roundTrip(SampleData.session()) }
    func testSpeciesCatalogRoundTrip() throws { try roundTrip(Species.initialCatalog) }

    func testEnvSnapshotWithAllFieldsRoundTrips() throws {
        var env = SampleData.snapshot(id: SampleData.snapshotID, at: SampleData.startedAt, isForecast: true)
        env.visibilityM = 12_000
        env.nextHighTideAt = SampleData.caughtAt
        env.nextLowTideAt = SampleData.endedAt
        env.waveDirectionDeg = 210
        env.swellHeightM = 0.2
        env.oceanCurrentMS = 0.1
        env.sunriseAt = SampleData.startedAt
        env.sunsetAt = SampleData.endedAt
        try roundTrip(env)
    }

    func testEmptyEnvSnapshotOmitsNilFields() throws {
        let env = EnvSnapshot(id: SampleData.snapshotID, at: SampleData.startedAt, coordinate: SampleData.hakodate)
        let json = try XCTUnwrap(String(data: try FogJSON.encode(env), encoding: .utf8))
        XCTAssertFalse(json.contains("airTemperatureC"))
        XCTAssertNotNil(json.range(of: #""isForecast"\s*:\s*false"#, options: .regularExpression), json)
        try roundTrip(env)
    }

    func testBlankSessionRoundTrips() throws {
        let blank = Session(id: SampleData.sessionID, spotID: SampleData.spotID, startedAt: SampleData.startedAt, endedAt: SampleData.endedAt)
        XCTAssertTrue(blank.isBlank)
        XCTAssertEqual(blank.duration, 9600)
        try roundTrip(blank)
    }

    func testActiveSessionHasNoEnd() throws {
        let active = Session(spotID: SampleData.spotID, startedAt: SampleData.startedAt)
        XCTAssertTrue(active.isActive)
        XCTAssertNil(active.duration)
        try roundTrip(active)
    }

    func testDatesAreISO8601UTC() throws {
        let data = try FogJSON.encode(SampleData.spot())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"2026-01-10T03:00:00.000Z\""), json)
    }

    func testDecoderAcceptsDatesWithoutFractionalSeconds() throws {
        let json = """
        {"id":"A0000000-0000-4000-8000-000000000001","name":"函館港","coordinate":{"latitude":41.7822,"longitude":140.7192},"isRegistered":true,"createdAt":"2026-01-10T03:00:00Z"}
        """
        let spot = try FogJSON.decode(Spot.self, from: Data(json.utf8))
        XCTAssertEqual(spot, SampleData.spot())
    }

    func testCheckedInFixtureMatchesSampleSession() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_session", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let decoded = try FogJSON.decode(Session.self, from: data)
        XCTAssertEqual(decoded, SampleData.session())
        try roundTrip(decoded)
    }
}

final class ModelBehaviourTests: XCTestCase {
    func testRigDisplayName() {
        XCTAssertEqual(SampleData.rig().displayName, "14g バグアンツ3\"")
        XCTAssertEqual(Rig(sinkerGrams: 10.5, hookSize: "#2", worm: "").displayName, "10.5g")
        XCTAssertEqual(Rig(name: "定番", sinkerGrams: 14, hookSize: "#1", worm: "x").displayName, "定番")
    }

    func testSpeciesLookupByAlias() {
        XCTAssertEqual(Species.lookup("アブラコ")?.id, "ainame")
        XCTAssertEqual(Species.lookup("ガヤ")?.name, "エゾメバル")
        XCTAssertEqual(Species.lookup("クロソイ")?.id, "kurosoi")
        XCTAssertNil(Species.lookup("マグロ"))
    }

    func testSpeciesCatalogIDsAreUnique() {
        let ids = Species.initialCatalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCatchSizeMeasured() {
        XCTAssertTrue(SampleData.catchRecord().isSizeMeasured)
        var c = SampleData.catchRecord()
        c.lengthCm = nil
        XCTAssertFalse(c.isSizeMeasured)
    }
}
