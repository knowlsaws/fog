import XCTest
@testable import Core

final class JapaneseHolidaysTests: XCTestCase {
    func testWeekday() {
        XCTAssertEqual(JapaneseHolidays.weekday(year: 1970, month: 1, day: 1), 5) // 木
        XCTAssertEqual(JapaneseHolidays.weekday(year: 2026, month: 11, day: 4), 4) // 水
        XCTAssertEqual(JapaneseHolidays.weekday(year: 2026, month: 11, day: 1), 1) // 日
    }

    func testCivilRoundTrip() {
        for (y, m, d) in [(2000, 2, 29), (2026, 11, 4), (2099, 12, 31), (1999, 1, 1)] {
            let o = JapaneseHolidays.ordinal(year: y, month: m, day: d)
            let c = JapaneseHolidays.civil(ordinal: o)
            XCTAssertEqual(c.0, y); XCTAssertEqual(c.1, m); XCTAssertEqual(c.2, d)
        }
    }

    func testFixedAndMondayHolidays2026() {
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 1, day: 1), "元日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 1, day: 12), "成人の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 2, day: 11), "建国記念の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 2, day: 23), "天皇誕生日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 3, day: 20), "春分の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 7, day: 20), "海の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 9, day: 21), "敬老の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 9, day: 23), "秋分の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 10, day: 12), "スポーツの日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 11, day: 3), "文化の日")
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 11, day: 23), "勤労感謝の日")
        XCTAssertNil(JapaneseHolidays.name(year: 2026, month: 11, day: 4))
    }

    func testSubstituteHoliday() {
        // 2026-05-03 憲法記念日が日曜 → 5/6（水）が振替休日
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 5, day: 6), "振替休日")
        XCTAssertNil(JapaneseHolidays.name(year: 2026, month: 5, day: 7))
        // 2025-11-23 勤労感謝の日が日曜 → 11/24 が振替休日
        XCTAssertEqual(JapaneseHolidays.name(year: 2025, month: 11, day: 24), "振替休日")
        // 2026-02-11 は水曜なので翌日は平日
        XCTAssertNil(JapaneseHolidays.name(year: 2026, month: 2, day: 12))
    }

    func testCitizensHoliday() {
        // 2026-09-22（火）は敬老の日 9/21 と秋分の日 9/23 に挟まれた国民の休日
        XCTAssertEqual(JapaneseHolidays.name(year: 2026, month: 9, day: 22), "国民の休日")
        XCTAssertTrue(JapaneseHolidays.isHoliday(year: 2026, month: 9, day: 22))
    }

    func testEquinoxes() {
        XCTAssertEqual(JapaneseHolidays.vernalEquinoxDay(2024), 20)
        XCTAssertEqual(JapaneseHolidays.vernalEquinoxDay(2025), 20)
        XCTAssertEqual(JapaneseHolidays.autumnalEquinoxDay(2024), 22)
        XCTAssertEqual(JapaneseHolidays.autumnalEquinoxDay(2025), 23)
        XCTAssertEqual(JapaneseHolidays.autumnalEquinoxDay(2027), 23)
    }
}
