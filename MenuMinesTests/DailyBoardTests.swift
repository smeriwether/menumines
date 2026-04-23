import XCTest
@testable import MenuMines

final class DailyBoardTests: XCTestCase {
    func testSeedFromDateUsesUTCComponents() {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else {
            XCTFail("Missing UTC time zone")
            return
        }
        calendar.timeZone = utc

        var components = DateComponents()
        components.calendar = calendar
        components.year = 2024
        components.month = 3
        components.day = 15
        components.hour = 12
        components.minute = 34

        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to construct date")
            return
        }

        XCTAssertEqual(seedFromDate(date), 20240315)
    }

    func testSeedFromDateIsUTCConsistent() {
        var calendar = Calendar(identifier: .gregorian)
        guard let pacific = TimeZone(identifier: "America/Los_Angeles") else {
            XCTFail("Missing Pacific time zone")
            return
        }
        calendar.timeZone = pacific

        var components = DateComponents()
        components.calendar = calendar
        components.year = 2024
        components.month = 3
        components.day = 14
        components.hour = 17
        components.minute = 0

        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to construct date")
            return
        }

        // 2024-03-14 17:00 in Los Angeles is 2024-03-15 00:00 UTC.
        XCTAssertEqual(seedFromDate(date), 20240315)
    }

    func testBoardForDateIsDeterministic() {
        let date = Date(timeIntervalSince1970: 1_710_465_600) // 2024-03-15 00:00:00 UTC
        let board1 = boardForDate(date)
        let board2 = boardForDate(date)

        XCTAssertEqual(board1.cells, board2.cells)
    }

    func testDifferentDaysProduceDifferentBoards() {
        // 2024-03-15 00:00:00 UTC
        let date1 = Date(timeIntervalSince1970: 1_710_465_600)
        // 2024-03-16 00:00:00 UTC (24 hours later)
        let date2 = Date(timeIntervalSince1970: 1_710_465_600 + 86400)

        let board1 = boardForDate(date1)
        let board2 = boardForDate(date2)

        XCTAssertNotEqual(board1.cells, board2.cells)
        XCTAssertEqual(seedFromDate(date1), 20240315)
        XCTAssertEqual(seedFromDate(date2), 20240316)
    }

    func testLateNightUTCConsistency() {
        // 2024-03-15 00:00:00 UTC (start of day)
        let startOfDay = Date(timeIntervalSince1970: 1_710_465_600)
        // 2024-03-15 23:00:00 UTC (late night same day)
        let lateNight = Date(timeIntervalSince1970: 1_710_465_600 + 23 * 3600)

        XCTAssertEqual(seedFromDate(startOfDay), seedFromDate(lateNight))
        XCTAssertEqual(seedFromDate(lateNight), 20240315)

        let board1 = boardForDate(startOfDay)
        let board2 = boardForDate(lateNight)
        XCTAssertEqual(board1.cells, board2.cells)
    }

    // MARK: - Stats Recording Tests

    private func clearStats() {
        let todaySeed = seedFromDate(Date())
        UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(todaySeed)")
    }

    override func tearDown() {
        super.tearDown()
        clearStats()
    }

    func testHasStatsBeenRecordedDefaultsFalse() {
        clearStats()
        XCTAssertFalse(hasStatsBeenRecorded())
    }

    func testRecordStatsSucceedsFirstTime() {
        clearStats()
        let result = recordStats(won: true, elapsedTime: 100.0, flagCount: 5)
        XCTAssertTrue(result)
        XCTAssertTrue(hasStatsBeenRecorded())
    }

    func testRecordStatsFailsSecondTime() {
        clearStats()
        _ = recordStats(won: true, elapsedTime: 100.0, flagCount: 5)
        let result = recordStats(won: false, elapsedTime: 200.0, flagCount: 10)
        XCTAssertFalse(result, "Second recording should fail")
    }

    func testGetStatsReturnsRecordedData() {
        clearStats()
        _ = recordStats(won: true, elapsedTime: 123.5, flagCount: 7)

        let stats = getStats(for: Date())
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.won, true)
        XCTAssertEqual(stats?.elapsedTime, 123.5)
        XCTAssertEqual(stats?.flagCount, 7)
    }

    func testRecordStatsForSeedUsesProvidedSeed() {
        clearStats()
        let seed: Int64 = 20260125
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(seed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(seed)")
        }

        let result = recordStats(forSeed: seed, won: false, elapsedTime: 42, flagCount: 3)

        XCTAssertTrue(result)
        XCTAssertTrue(hasStatsBeenRecorded(forSeed: seed))
        XCTAssertEqual(getStats(forSeed: seed), DailyStats(seed: seed, won: false, elapsedTime: 42, flagCount: 3))
    }

    func testRecordStatsForSeedDedupesWhenMarkerMovedToAnotherSeed() {
        clearStats()
        let firstSeed: Int64 = 20260125
        let secondSeed: Int64 = 20260126
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(firstSeed)")
        UserDefaults.standard.removeObject(forKey: "dailyStats_\(secondSeed)")
        defer {
            UserDefaults.standard.removeObject(forKey: "dailyStatsRecordedSeed")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(firstSeed)")
            UserDefaults.standard.removeObject(forKey: "dailyStats_\(secondSeed)")
        }

        XCTAssertTrue(recordStats(forSeed: firstSeed, won: true, elapsedTime: 100, flagCount: 4))
        XCTAssertTrue(recordStats(forSeed: secondSeed, won: false, elapsedTime: 200, flagCount: 5))

        let duplicate = recordStats(forSeed: firstSeed, won: false, elapsedTime: 50, flagCount: 1)

        XCTAssertFalse(duplicate)
        XCTAssertEqual(getStats(forSeed: firstSeed)?.won, true)
        XCTAssertEqual(getStats(forSeed: firstSeed)?.elapsedTime, 100)
    }

    func testGetStatsReturnsNilWhenNotRecorded() {
        clearStats()
        let stats = getStats(for: Date())
        XCTAssertNil(stats)
    }

    func testDailyStatsIsCodable() throws {
        let original = DailyStats(seed: 20260125, won: true, elapsedTime: 99.0, flagCount: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailyStats.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
