import AppKit
import Foundation
import Sentry

/// The current status of the game.
enum GameStatus: String, Equatable, Codable {
    case notStarted
    case playing
    case won
    case lost
}

/// Direction for keyboard navigation.
enum Direction {
    case up, down, left, right
}

/// Observable game state that owns the board and manages game logic.
@Observable
final class GameState {
    // Note: internal(set) allows GamePersistenceCoordinator and checkContinuousPlaySetting to set these
    internal(set) var board: Board
    internal(set) var status: GameStatus = .notStarted
    internal(set) var elapsedTime: TimeInterval = 0
    internal(set) var flagCount: Int = 0
    internal(set) var selectedRow: Int = 0
    internal(set) var selectedCol: Int = 0
    internal(set) var dailySeed: Int64
    internal(set) var puzzleType: PuzzleType = .daily
    private(set) var isPaused: Bool = false
    /// Count of correctly marked mines at the time of winning (before auto-flagging).
    /// Used for share text to show player's actual skill.
    private var markedMinesAtWin: Int = 0

    /// Timer for tracking elapsed game time.
    private let gameTimer = GameTimer()
    /// Handles VoiceOver announcements with debouncing.
    private let announcer = AccessibilityAnnouncer()
    /// Cache the last UTC daily seed we checked for rollover to avoid redundant calculations
    private var lastRolloverCheckSeed: Int64?

    /// Whether continuous play mode is enabled.
    private var isContinuousPlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.SettingsKeys.continuousPlay)
    }

    /// Whether reset is allowed.
    /// Reset is locked once today's puzzle is completed unless continuous play is enabled.
    var canReset: Bool {
        if isDailyPuzzleComplete() {
            return isContinuousPlayEnabled
        }
        return true
    }

    init(board: Board, dailySeed: Int64 = seedFromDate(Date()), puzzleType: PuzzleType = .daily) {
        self.board = board
        self.dailySeed = dailySeed
        self.puzzleType = puzzleType
        gameTimer.onTick = { [weak self] in
            self?.elapsedTime += 1
        }
    }

    /// Generates a Wordle-style share text for the completed game.
    /// The grid encodes only the revealed/marked/hidden outcome without exposing mine locations.
    /// - Parameter date: The date to use for the header (defaults to current date formatted in UTC).
    /// - Returns: The formatted share text, or nil if the game is not complete.
    func shareText(for date: Date = Date()) -> String? {
        ShareTextGenerator.generate(
            status: status,
            board: board,
            elapsedTime: elapsedTime,
            markedMinesCount: countCorrectlyMarkedMines(),
            date: date
        )
    }

    /// Counts the number of flags placed on actual mines.
    /// For won games, returns the count captured before auto-flagging to reflect player skill.
    private func countCorrectlyMarkedMines() -> Int {
        if status == .won {
            return markedMinesAtWin
        }
        return countFlaggedMines()
    }

    /// Reveals the cell at the given position.
    /// If the cell is already revealed with a number, performs a chord reveal instead.
    func reveal(row: Int, col: Int) {
        guard status == .notStarted || status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        if case .revealed(let adjacentMines) = board.cells[row][col].state, adjacentMines > 0 {
            chordReveal(row: row, col: col)
            return
        }

        guard case .hidden = board.cells[row][col].state else { return }

        let isFirstClick = (status == .notStarted)
        if isFirstClick {
            board.clearAreaForOpening(centerRow: row, centerCol: col, seed: dailySeed)
            startTimer()
            status = .playing
        }

        let result = board.reveal(row: row, col: col)

        switch result {
        case .mine:
            status = .lost
            board.revealAllMines()
            handleGameComplete(won: false)
        case .safe:
            if checkWinCondition() {
                markedMinesAtWin = countFlaggedMines()
                status = .won
                board.flagAllMines()
                flagCount = Board.mineCount
                handleGameComplete(won: true)
            }
        }
    }

    /// Counts the number of flags currently placed on mines.
    private func countFlaggedMines() -> Int {
        var count = 0
        for row in board.cells {
            for cell in row {
                if case .flagged = cell.state, cell.hasMine {
                    count += 1
                }
            }
        }
        return count
    }

    /// Toggles the flag on the cell at the given position.
    /// Flags are only allowed after the game has started (first reveal).
    func toggleFlag(row: Int, col: Int) {
        guard status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        let previousState = board.cells[row][col].state
        board.toggleFlag(row: row, col: col)
        let newState = board.cells[row][col].state

        // Update flag count
        if case .flagged = newState {
            flagCount += 1
        } else if case .flagged = previousState {
            if flagCount > 0 {
                flagCount -= 1
            } else {
                // This should never happen in normal operation - log for debugging
                SentrySDK.capture(message: "Attempted to decrement flagCount below zero") { [self] scope in
                    scope.setLevel(.warning)
                    scope.setContext(value: [
                        "row": row,
                        "col": col,
                        "flag_count": flagCount,
                        "daily_seed": dailySeed
                    ], key: "flag_underflow")
                }
            }
        }
    }

    /// Resets the game to a fresh state.
    /// If continuous play is enabled and daily puzzle is complete, starts a random puzzle.
    /// Otherwise resets to today's daily puzzle.
    /// Does nothing if reset is locked (daily puzzle already completed and continuous play disabled).
    func reset() {
        guard canReset else { return }
        stopTimer()
        announcer.cancelPendingAnnouncement()

        // If continuous play is enabled and daily is complete, start a random puzzle
        if isContinuousPlayEnabled && isDailyPuzzleComplete() {
            resetToRandomPuzzle()
        } else {
            // Reset to today's daily puzzle
            let seed = seedFromDate(Date())
            board = Board(seed: seed)
            dailySeed = seed
            puzzleType = .daily
            status = .notStarted
            elapsedTime = 0
            flagCount = 0
            selectedRow = 0
            selectedCol = 0
            GameSnapshot.clear()
        }
    }

    /// Resets to a new random puzzle for continuous play mode.
    private func resetToRandomPuzzle() {
        let randomSeed = generateRandomSeed()
        board = Board(seed: randomSeed)
        dailySeed = randomSeed
        puzzleType = .random
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        selectedRow = 0
        selectedCol = 0
        // Don't persist random puzzles
        GameSnapshot.clear()
    }

    /// Generates a random seed that won't collide with daily seeds (YYYYMMDD format).
    /// Uses negative values to ensure no collision.
    private func generateRandomSeed() -> Int64 {
        -Int64.random(in: 1...Int64.max)
    }

    // MARK: - Persistence

    /// Saves the current game state to persistent storage.
    /// Saves in-progress and completed daily games so state persists across app restarts.
    /// Does not save if game hasn't started yet or if it's a random puzzle.
    func save() {
        guard status != .notStarted else { return }
        // Don't persist random puzzles - they're discarded on app close
        guard puzzleType == .daily else { return }

        let snapshot = GameSnapshot(
            board: board,
            status: status,
            elapsedTime: elapsedTime,
            flagCount: flagCount,
            selectedRow: selectedRow,
            selectedCol: selectedCol,
            dailySeed: dailySeed,
            puzzleType: puzzleType
        )
        snapshot.save()
    }

    /// Creates a GameState by restoring from a saved snapshot or stats if available,
    /// otherwise creates a fresh game with today's daily board.
    /// Delegates to GamePersistenceCoordinator for centralized persistence logic.
    static func restored() -> GameState {
        GamePersistenceCoordinator.restore()
    }

    /// Pauses the timer (e.g., when popover closes).
    func pauseTimer() {
        if status == .playing {
            gameTimer.pause()
            isPaused = true
        } else {
            gameTimer.stop()
        }
    }

    /// Resumes the timer (e.g., when popover reopens).
    func resumeTimer() {
        guard status == .playing else { return }
        gameTimer.resume()
        isPaused = false
    }

    /// Checks if we should roll over to today's puzzle and performs the rollover if needed.
    /// Called when the popover appears to handle day changes.
    ///
    /// Rollover happens when:
    /// - The current game is a daily puzzle (not random)
    /// - The current game's seed is from a previous day
    /// - AND the game is not in progress (status != .playing)
    ///
    /// If game is in progress, it continues until completion.
    /// Random puzzles are not date-bound and skip rollover checks.
    func checkForDailyRollover() {
        // Random puzzles are not tied to dates - skip rollover check
        guard puzzleType == .daily else { return }

        let todaySeed = seedFromDate(Date())

        // Check if we've already checked this UTC day (cache optimization)
        if lastRolloverCheckSeed == todaySeed, dailySeed == todaySeed {
            return
        }

        // Already on today's puzzle
        guard dailySeed != todaySeed else {
            lastRolloverCheckSeed = todaySeed
            return
        }

        // Game is in progress - delay rollover
        guard status != .playing else { return }

        // Roll over to today's puzzle
        rolloverToNewDay(seed: todaySeed)
        lastRolloverCheckSeed = todaySeed
    }

    /// Performs a rollover to a new day's puzzle.
    private func rolloverToNewDay(seed: Int64) {
        stopTimer()
        announcer.cancelPendingAnnouncement()
        board = Board(seed: seed)
        dailySeed = seed
        puzzleType = .daily
        status = .notStarted
        elapsedTime = 0
        flagCount = 0
        // Reset to top-left cell selection
        selectedRow = 0
        selectedCol = 0
        GameSnapshot.clear()
        // Clear daily namespace too since we're starting a new day
        GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) { GameSnapshot.clear() }
    }

    /// Checks if continuous play was disabled while on a random puzzle.
    /// If so, restores the completed daily puzzle state.
    ///
    /// This handles the scenario where:
    /// 1. User completes daily puzzle with continuous play enabled
    /// 2. User plays random puzzles
    /// 3. User disables continuous play
    /// 4. User should now see their completed daily puzzle (locked)
    func checkContinuousPlaySetting() {
        // Only applies when on a random puzzle with continuous play disabled
        guard puzzleType == .random, !isContinuousPlayEnabled else { return }

        // If daily is complete, restore that state using the coordinator
        guard isDailyPuzzleComplete() else { return }

        stopTimer()

        // Get the restored daily state from the coordinator and copy its values
        let restored = GamePersistenceCoordinator.restore()
        board = restored.board
        dailySeed = restored.dailySeed
        status = restored.status
        elapsedTime = restored.elapsedTime
        flagCount = restored.flagCount
        selectedRow = restored.selectedRow
        selectedCol = restored.selectedCol
        puzzleType = restored.puzzleType
    }

    /// Moves the keyboard selection in the given direction.
    func moveSelection(_ direction: Direction) {
        let oldRow = selectedRow
        let oldCol = selectedCol

        switch direction {
        case .up:
            selectedRow = max(0, selectedRow - 1)
        case .down:
            selectedRow = min(Board.rows - 1, selectedRow + 1)
        case .left:
            selectedCol = max(0, selectedCol - 1)
        case .right:
            selectedCol = min(Board.cols - 1, selectedCol + 1)
        }

        if selectedRow != oldRow || selectedCol != oldCol {
            announceSelectedCell()
        }
    }

    /// Announces the currently selected cell for VoiceOver users.
    /// Debounced to prevent overlapping announcements during rapid navigation.
    private func announceSelectedCell() {
        let cell = board.cells[selectedRow][selectedCol]
        announcer.announceSelectionChange(row: selectedRow, col: selectedCol, cell: cell)
    }

    /// Reveals the currently selected cell.
    func revealSelected() {
        reveal(row: selectedRow, col: selectedCol)
    }

    /// Toggles the flag on the currently selected cell.
    func toggleFlagSelected() {
        toggleFlag(row: selectedRow, col: selectedCol)
    }

    /// Performs a chord reveal on the cell at the given position.
    func chordReveal(row: Int, col: Int) {
        guard status == .playing else { return }
        guard row >= 0, row < Board.rows, col >= 0, col < Board.cols else { return }

        switch board.chordReveal(row: row, col: col) {
        case .mine:
            status = .lost
            board.revealAllMines()
            handleGameComplete(won: false)
        case .safe:
            if checkWinCondition() {
                markedMinesAtWin = countFlaggedMines()
                status = .won
                board.flagAllMines()
                flagCount = Board.mineCount
                handleGameComplete(won: true)
            }
        }
    }

    /// Performs a chord reveal on the currently selected cell.
    func chordRevealSelected() {
        chordReveal(row: selectedRow, col: selectedCol)
    }

    // MARK: - Private

    private func startTimer() {
        gameTimer.start()
    }

    private func stopTimer() {
        gameTimer.stop()
        isPaused = false
    }

    /// Records the game result to the stats store.
    private func recordGameResult(won: Bool) {
        let result = GameResult(
            won: won,
            elapsedTime: elapsedTime,
            dailySeed: dailySeed,
            puzzleType: puzzleType
        )
        Task { @MainActor in
            StatsStore.shared.record(result)
        }
    }

    private func checkWinCondition() -> Bool {
        for row in board.cells {
            for cell in row where !cell.hasMine {
                guard case .revealed = cell.state else {
                    return false
                }
            }
        }
        return true
    }

    /// Handles game completion (win or loss).
    /// For daily puzzles: marks complete, records stats, saves state, and saves to daily namespace.
    /// For random puzzles: records stats only (no daily tracking).
    private func handleGameComplete(won: Bool) {
        stopTimer()

        if puzzleType == .daily {
            // Only mark daily completion and record daily stats for daily puzzles
            markCompleteAndRecordStats(forSeed: dailySeed, won: won, elapsedTime: elapsedTime, flagCount: flagCount)

            // Save to daily namespace for restoration when continuous play is toggled off.
            // This is intentionally a separate save from save() below - the daily namespace
            // preserves the completed board state even when the user plays random puzzles,
            // allowing correct visual restoration when toggling continuous play off.
            let snapshot = GameSnapshot(
                board: board,
                status: status,
                elapsedTime: elapsedTime,
                flagCount: flagCount,
                selectedRow: selectedRow,
                selectedCol: selectedCol,
                dailySeed: dailySeed,
                puzzleType: puzzleType
            )
            GameSnapshot.withStorageKey(GameSnapshot.dailyNamespace) {
                snapshot.save()
            }
        }

        recordGameResult(won: won)
        save()
    }
}
