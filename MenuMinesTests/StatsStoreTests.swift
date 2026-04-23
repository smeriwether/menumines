import Foundation
import Testing
@testable import MenuMines

@Suite("StatsStore Tests", .serialized)
struct StatsStoreTests {

    private let testResultsKey = "gameResults"

    private func clearStats() {
        UserDefaults.standard.removeObject(forKey: testResultsKey)
    }

    private func makeResult(
        won: Bool,
        elapsedTime: TimeInterval = 120,
        dailySeed: Int64 = 20260125,
        completedAt: Date = Date()
    ) -> GameResult {
        GameResult(won: won, elapsedTime: elapsedTime, dailySeed: dailySeed, completedAt: completedAt)
    }

    // MARK: - Empty State

    @Test("Empty store has no games played")
    func testEmptyStoreHasNoGamesPlayed() {
        let store = StatsStore.forTesting()
        #expect(store.gamesPlayed == 0)
        #expect(store.wins == 0)
        #expect(store.winRate == nil)
        #expect(store.bestTime == nil)
        #expect(store.averageTime == nil)
        #expect(store.trackedSince == nil)
        #expect(!store.hasResults)
        #expect(store.currentStreak == 0)
        #expect(store.longestStreak == 0)
    }

    // MARK: - Games Played

    @Test("Games played counts all results")
    func testGamesPlayedCountsAllResults() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: true)
        ])
        #expect(store.gamesPlayed == 3)
    }

    // MARK: - Wins

    @Test("Wins counts only winning games")
    func testWinsCountsOnlyWinningGames() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: true),
            makeResult(won: false)
        ])
        #expect(store.wins == 2)
    }

    // MARK: - Win Rate

    @Test("Win rate calculates correctly")
    func testWinRateCalculatesCorrectly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true),
            makeResult(won: false),
            makeResult(won: false)
        ])
        #expect(store.winRate == 50)
    }

    @Test("Win rate rounds to whole percent")
    func testWinRateRoundsToWholePercent() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true),
            makeResult(won: false)
        ])
        // 2/3 = 66.67% -> rounds to 67%
        #expect(store.winRate == 67)
    }

    @Test("Win rate is 100% when all wins")
    func testWinRateIs100WhenAllWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: true)
        ])
        #expect(store.winRate == 100)
    }

    @Test("Win rate is 0% when no wins")
    func testWinRateIs0WhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false),
            makeResult(won: false)
        ])
        #expect(store.winRate == 0)
    }

    // MARK: - Best Time

    @Test("Best time is minimum of wins only")
    func testBestTimeIsMinimumOfWinsOnly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, elapsedTime: 120),
            makeResult(won: false, elapsedTime: 50),  // Should be ignored
            makeResult(won: true, elapsedTime: 90),
            makeResult(won: true, elapsedTime: 150)
        ])
        #expect(store.bestTime == 90)
    }

    @Test("Best time is nil when no wins")
    func testBestTimeIsNilWhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false, elapsedTime: 50)
        ])
        #expect(store.bestTime == nil)
    }

    // MARK: - Average Time

    @Test("Average time is calculated from wins only")
    func testAverageTimeIsCalculatedFromWinsOnly() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, elapsedTime: 100),
            makeResult(won: false, elapsedTime: 50),  // Should be ignored
            makeResult(won: true, elapsedTime: 200)
        ])
        #expect(store.averageTime == 150)
    }

    @Test("Average time is nil when no wins")
    func testAverageTimeIsNilWhenNoWins() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: false, elapsedTime: 100)
        ])
        #expect(store.averageTime == nil)
    }

    // MARK: - Tracked Since

    @Test("Tracked since is earliest result date")
    func testTrackedSinceIsEarliestResultDate() {
        let earliest = Date(timeIntervalSince1970: 1000)
        let middle = Date(timeIntervalSince1970: 2000)
        let latest = Date(timeIntervalSince1970: 3000)

        let store = StatsStore.forTesting(with: [
            makeResult(won: true, completedAt: latest),
            makeResult(won: false, completedAt: earliest),
            makeResult(won: true, completedAt: middle)
        ])
        #expect(store.trackedSince == earliest)
    }

    // MARK: - Streaks

    @Test("Current streak counts consecutive days ending at most recent completion")
    func testCurrentStreakCountsMostRecentRun() throws {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: false, dailySeed: 20260126),
            makeResult(won: true, dailySeed: 20260128)
        ])
        let asOfDate = try #require(dateFromSeed(20260128))

        #expect(store.currentStreak(asOf: asOfDate) == 1)
        #expect(store.longestStreak == 2)
    }

    @Test("Current streak is zero when latest completion is stale")
    func testCurrentStreakIsZeroWhenLatestCompletionIsStale() throws {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: false, dailySeed: 20260126),
            makeResult(won: true, dailySeed: 20260127)
        ])
        let asOfDate = try #require(dateFromSeed(20260201))

        #expect(store.currentStreak(asOf: asOfDate) == 0)
        #expect(store.longestStreak == 3)
    }

    @Test("Longest streak counts the maximum consecutive run")
    func testLongestStreakCountsMaximumRun() throws {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260125),
            makeResult(won: true, dailySeed: 20260126),
            makeResult(won: false, dailySeed: 20260127),
            makeResult(won: true, dailySeed: 20260129)
        ])
        let asOfDate = try #require(dateFromSeed(20260129))

        #expect(store.currentStreak(asOf: asOfDate) == 1)
        #expect(store.longestStreak == 3)
    }

    @Test("Streaks count across month boundaries")
    func testStreaksCountAcrossMonthBoundaries() throws {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true, dailySeed: 20260131),
            makeResult(won: true, dailySeed: 20260201)
        ])
        let asOfDate = try #require(dateFromSeed(20260201))

        #expect(store.currentStreak(asOf: asOfDate) == 2)
        #expect(store.longestStreak == 2)
    }

    @Test("Daily results by seed includes daily results only")
    func testDailyResultsBySeedIncludesDailyResultsOnly() {
        let daily = makeResult(won: true, dailySeed: 20260125)
        let random = GameResult(won: false, elapsedTime: 30, dailySeed: -123, puzzleType: .random)
        let store = StatsStore.forTesting(with: [daily, random])

        #expect(store.dailyResultsBySeed[20260125] == daily)
        #expect(store.dailyResultsBySeed[-123] == nil)
    }

    @Test("Daily result lookup handles duplicate legacy seeds")
    func testDailyResultLookupHandlesDuplicateLegacySeeds() {
        let older = makeResult(won: true, elapsedTime: 120, dailySeed: 20260125)
        let newer = makeResult(won: false, elapsedTime: 90, dailySeed: 20260125)
        let store = StatsStore.forTesting(with: [newer, older])

        #expect(store.dailyResult(forSeed: 20260125) == newer)
    }

    // MARK: - Recording

    @Test("Recording a result adds it to the store")
    @MainActor
    func testRecordingResultAddsToStore() {
        clearStats()
        let store = StatsStore.forTesting()
        let result = makeResult(won: true)

        store.record(result)

        #expect(store.gamesPlayed == 1)
        #expect(store.wins == 1)
    }

    // MARK: - Deduplication

    @Test("Recording with same dailySeed replaces existing result")
    @MainActor
    func testRecordDeduplicatesByDailySeed() {
        clearStats()
        let store = StatsStore.forTesting()
        let seed: Int64 = 20260125

        // Record first result for today
        let result1 = makeResult(won: true, elapsedTime: 100, dailySeed: seed)
        store.record(result1)
        #expect(store.gamesPlayed == 1)
        #expect(store.bestTime == 100)

        // Record second result with same seed - should be ignored
        let result2 = makeResult(won: true, elapsedTime: 50, dailySeed: seed)
        store.record(result2)
        #expect(store.gamesPlayed == 1, "Should still have 1 game, not 2")
        #expect(store.bestTime == 100, "Should keep first result's time")
    }

    @Test("Recording with different dailySeed adds new result")
    @MainActor
    func testRecordAllowsDifferentSeeds() {
        clearStats()
        let store = StatsStore.forTesting()

        // Record for different days
        let result1 = makeResult(won: true, elapsedTime: 100, dailySeed: 20260125)
        let result2 = makeResult(won: true, elapsedTime: 80, dailySeed: 20260126)
        store.record(result1)
        store.record(result2)

        #expect(store.gamesPlayed == 2, "Should have 2 games from different days")
        #expect(store.bestTime == 80, "Best time should be from faster game")
    }

    // MARK: - Reset

    @Test("Reset clears all results")
    @MainActor
    func testResetClearsAllResults() {
        let store = StatsStore.forTesting(with: [
            makeResult(won: true),
            makeResult(won: false)
        ])

        store.reset()

        #expect(store.gamesPlayed == 0)
        #expect(!store.hasResults)
    }

    // MARK: - Persistence

    @Test("Stats persist to UserDefaults")
    @MainActor
    func testStatsPersistToUserDefaults() {
        clearStats()
        let store = StatsStore.forTesting()
        let result = makeResult(won: true, elapsedTime: 100)

        store.record(result)

        guard let data = UserDefaults.standard.data(forKey: testResultsKey) else {
            Issue.record("Expected data to be saved to UserDefaults")
            return
        }

        guard let decoded = try? JSONDecoder().decode([GameResult].self, from: data) else {
            Issue.record("Expected data to be decodable")
            return
        }

        #expect(decoded.count == 1)
        #expect(decoded[0].won == true)
        #expect(decoded[0].elapsedTime == 100)
    }
}
