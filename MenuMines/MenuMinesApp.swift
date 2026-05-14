import AppKit
import Sentry
import SwiftUI

@main
struct MenuMinesApp: App {
    @State private var gameState: GameState
    @AppStorage(Constants.SettingsKeys.showMenuBarIndicators) private var showMenuBarIndicators = true

    private static var eventMonitor: Any?

    #if DEBUG
    private static var isScreenshotExportMode: Bool {
        ProcessInfo.processInfo.environment["MENUMINES_EXPORT_APP_STORE_SCREENSHOTS"] == "1"
    }
    #endif

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static var sentryDsn: String? {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String else {
            return nil
        }
        let trimmed = dsn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func startSentryIfNeeded() {
        guard !isDebugBuild, !isRunningTests else { return }
        guard let dsn = sentryDsn else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 1.0
            options.enableAutoSessionTracking = true
        }
    }

    private static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Constants.SettingsKeys.continuousPlay: true
        ])
    }

    init() {
        Self.startSentryIfNeeded()
        Self.registerDefaults()

        #if DEBUG
        let state = Self.isScreenshotExportMode
            ? GameState(board: Board(seed: AppStoreScreenshotVariant.seed), puzzleType: .random)
            : GameState.restored()
        #else
        let state = GameState.restored()
        #endif

        _gameState = State(initialValue: state)

        #if DEBUG
        if Self.isScreenshotExportMode {
            Task { @MainActor in
                do {
                    try AppStoreScreenshotExporter.exportAll()
                    NSApplication.shared.terminate(nil)
                } catch {
                    fputs("Failed to export App Store screenshots: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        #endif

        Self.setupKeyboardMonitor(for: state)
        Self.setupTerminationObserver(for: state)
    }

    private static func setupTerminationObserver(for gameState: GameState) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            gameState.save()
        }
    }

    private static func setupKeyboardMonitor(for gameState: GameState) {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Arrow keys for navigation
            switch event.keyCode {
            case 123: gameState.moveSelection(.left)
            case 124: gameState.moveSelection(.right)
            case 125: gameState.moveSelection(.down)
            case 126: gameState.moveSelection(.up)
            default:
                // Character-based keys
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    switch chars {
                    case " ":
                        gameState.revealSelected()
                    case "f":
                        gameState.toggleFlagSelected()
                    default:
                        return event
                    }
                } else {
                    return event
                }
            }
            return nil
        }
    }

    private var currentIconState: MenuBarIconState {
        guard showMenuBarIndicators else {
            return .normal
        }
        return menuBarIconState(
            gameStatus: gameState.status,
            isPaused: gameState.isPaused,
            isDailyComplete: isDailyPuzzleComplete()
        )
    }

    var body: some Scene {
        appScenes
    }

    @SceneBuilder
    private var appScenes: some Scene {
        MenuBarExtra {
            MenuContentView(gameState: gameState)
        } label: {
            MenuBarIconView(
                state: currentIconState,
                elapsedTime: gameState.elapsedTime,
                currentStreak: StatsStore.shared.currentStreak
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }

        Window(String(localized: "stats_window_title"), id: "stats") {
            StatsWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

#if DEBUG
private enum AppStoreScreenshotVariant: String, CaseIterable {
    case daily
    case playing
    case complete

    static let seed: Int64 = 20260513

    var fileName: String {
        switch self {
        case .daily:
            return "01-daily-puzzle.png"
        case .playing:
            return "02-fast-play.png"
        case .complete:
            return "03-daily-result.png"
        }
    }

    var title: String {
        switch self {
        case .daily:
            return "A fresh puzzle every day"
        case .playing:
            return "Minesweeper without leaving your work"
        case .complete:
            return "Finish once, then come back tomorrow"
        }
    }

    var subtitle: String {
        switch self {
        case .daily:
            return "The same 9x9 daily board for everyone, always one click away in the menu bar."
        case .playing:
            return "Reveal cells, flag mines, and keep the board tucked into a compact macOS popover."
        case .complete:
            return "Daily results lock in after a win or loss, with local stats and a shareable grid."
        }
    }

    var accentColor: Color {
        switch self {
        case .daily:
            return Color(red: 0.98, green: 0.76, blue: 0.25)
        case .playing:
            return Color(red: 0.37, green: 0.86, blue: 0.66)
        case .complete:
            return Color(red: 0.48, green: 0.72, blue: 1.0)
        }
    }
}

@MainActor
private enum AppStoreScreenshotExporter {
    private static let canvasSize = CGSize(width: 1440, height: 900)
    private static let scale: CGFloat = 2

    static func exportAll() throws {
        let outputDirectory = outputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for variant in AppStoreScreenshotVariant.allCases {
            let view = AppStoreScreenshotCanvas(variant: variant)
                .frame(width: canvasSize.width, height: canvasSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale

            guard let image = renderer.nsImage,
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                throw CocoaError(.fileWriteUnknown)
            }

            let fileURL = outputDirectory.appendingPathComponent(variant.fileName)
            try pngData.write(to: fileURL, options: .atomic)
            print("Wrote \(fileURL.path)")
        }
    }

    private static func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["MENUMINES_SCREENSHOT_OUTPUT_DIR"],
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppStoreScreenshots", isDirectory: true)
    }
}

private struct AppStoreScreenshotCanvas: View {
    let variant: AppStoreScreenshotVariant

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.13),
                    Color(red: 0.05, green: 0.32, blue: 0.29),
                    Color(red: 0.11, green: 0.13, blue: 0.17)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                screenshotMenuBar

                HStack(alignment: .center, spacing: 88) {
                    copyBlock
                        .frame(width: 560, alignment: .leading)

                    ScreenshotMenuSurface(variant: variant)
                        .shadow(color: .black.opacity(0.36), radius: 34, x: 0, y: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 92)
                .padding(.bottom, 48)
            }
        }
        .foregroundStyle(.white)
    }

    private var screenshotMenuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(variant.accentColor)

            Text("MenuMines")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Text("9:41")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.76))
        }
        .padding(.horizontal, 28)
        .frame(height: 44)
        .background(.black.opacity(0.26))
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MenuMines")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(variant.accentColor)

            Text(variant.title)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(variant.subtitle)
                .font(.system(size: 24, weight: .medium))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScreenshotMenuSurface: View {
    let variant: AppStoreScreenshotVariant

    private var state: GameState {
        ScreenshotFixture.state(for: variant)
    }

    private var isComplete: Bool {
        state.status == .won || state.status == .lost
    }

    var body: some View {
        VStack(spacing: 12) {
            ScreenshotHeaderView(
                status: state.status,
                elapsedTime: state.elapsedTime,
                flagCount: state.flagCount,
                canReset: state.status != .won
            )

            ScreenshotGameBoardView(
                board: state.board,
                gameStatus: state.status,
                selectedRow: state.selectedRow,
                selectedCol: state.selectedCol,
                isFlagMode: variant == .playing
            )

            ScreenshotFooterView(
                isGameComplete: isComplete,
                puzzleType: .daily,
                isFlagMode: variant == .playing
            )
        }
        .padding()
        .frame(width: 300, height: 372, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        )
        .foregroundStyle(Color.primary)
    }
}

private struct ScreenshotHeaderView: View {
    let status: GameStatus
    let elapsedTime: TimeInterval
    let flagCount: Int
    let canReset: Bool

    private var timeDisplay: String {
        let totalSeconds = Int(elapsedTime)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var statusEmoji: String {
        switch status {
        case .notStarted, .playing:
            return "🙂"
        case .won:
            return "😎"
        case .lost:
            return "😵"
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text("🚩")
                Text("\(flagCount)/\(Board.mineCount)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            .frame(minWidth: 60, alignment: .leading)

            Spacer()

            Text(statusEmoji)
                .font(.system(size: 24))
                .opacity(canReset ? 1 : 0.75)

            Spacer()

            Text(timeDisplay)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }
}

private struct ScreenshotGameBoardView: View {
    let board: Board
    let gameStatus: GameStatus
    let selectedRow: Int
    let selectedCol: Int
    let isFlagMode: Bool

    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<Board.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<Board.cols, id: \.self) { col in
                        ScreenshotCellView(
                            cell: board.cells[row][col],
                            row: row,
                            col: col,
                            gameStatus: gameStatus,
                            isSelected: row == selectedRow && col == selectedCol,
                            isChordReady: isChordReady(row: row, col: col),
                            isFlagMode: isFlagMode
                        )
                    }
                }
            }
        }
        .background(Color(nsColor: .separatorColor))
    }

    private func isChordReady(row: Int, col: Int) -> Bool {
        guard gameStatus == .playing else { return false }
        guard case .revealed(let adjacentMines) = board.cells[row][col].state, adjacentMines > 0 else {
            return false
        }
        return board.adjacentFlagCount(row: row, col: col) == adjacentMines
    }
}

private struct ScreenshotCellView: View {
    let cell: Cell
    let row: Int
    let col: Int
    let gameStatus: GameStatus
    let isSelected: Bool
    let isChordReady: Bool
    let isFlagMode: Bool

    private static let cellSize: CGFloat = 28

    var body: some View {
        ZStack {
            background
            if isChordReady {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 2)
                    .padding(2)
            }
            content
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .overlay(selectionBorder)
    }

    @ViewBuilder
    private var background: some View {
        if cell.isExploded {
            Color.red
        } else if case .revealed = cell.state {
            Color(red: 0.88, green: 0.89, blue: 0.87)
        } else {
            ScreenshotRaisedCellBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        if cell.isExploded {
            Text("💣")
                .font(.system(size: 14))
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged:
                Text("🚩")
                    .font(.system(size: 14))
            case .revealed(let adjacentMines):
                if cell.hasMine {
                    Text("💣")
                        .font(.system(size: 14))
                } else if adjacentMines > 0 {
                    Text("\(adjacentMines)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(color(for: adjacentMines))
                }
            }
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 2)
        }
    }

    private func color(for adjacentMines: Int) -> Color {
        switch adjacentMines {
        case 1:
            return Color(red: 0.0, green: 0.0, blue: 1.0)
        case 2:
            return Color(red: 0.0, green: 0.5, blue: 0.0)
        case 3:
            return Color(red: 0.8, green: 0.0, blue: 0.0)
        case 4:
            return Color(red: 0.0, green: 0.0, blue: 0.55)
        case 5:
            return Color(red: 0.55, green: 0.27, blue: 0.07)
        case 6:
            return Color(red: 0.0, green: 0.55, blue: 0.55)
        case 7:
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        case 8:
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        default:
            return .primary
        }
    }
}

private struct ScreenshotRaisedCellBackground: View {
    private let bevelWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            let inset = bevelWidth

            ZStack {
                Color(red: 0.74, green: 0.76, blue: 0.74)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.62))

                Path { path in
                    path.move(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size, y: size))
                    path.addLine(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.34))
            }
        }
    }
}

private struct ScreenshotFooterView: View {
    let isGameComplete: Bool
    let puzzleType: PuzzleType
    let isFlagMode: Bool

    private var puzzleTypeLabel: String {
        switch puzzleType {
        case .daily:
            return String(localized: "puzzle_type_daily")
        case .random:
            return String(localized: "puzzle_type_random")
        }
    }

    private var puzzleTypeIconName: String {
        switch puzzleType {
        case .daily:
            return "calendar"
        case .random:
            return "shuffle"
        }
    }

    var body: some View {
        HStack {
            if isGameComplete {
                Text(String(localized: "share_button"))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .fixedSize()
            } else {
                HStack(spacing: 4) {
                    Image(systemName: puzzleTypeIconName)
                        .font(.caption)
                    Text(puzzleTypeLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .fixedSize()
            }

            Spacer()

            Image(systemName: isFlagMode ? "flag.fill" : "flag")
                .foregroundStyle(isFlagMode ? Color.accentColor : Color.primary)

            Image(systemName: "questionmark.circle")
                .foregroundStyle(Color.primary)

            Image(systemName: "gearshape")
                .foregroundStyle(Color.primary)
        }
        .font(.system(size: 14))
        .frame(width: 260)
    }
}

private enum ScreenshotFixture {
    static func state(for variant: AppStoreScreenshotVariant) -> GameState {
        switch variant {
        case .daily:
            let state = GameState(
                board: Board(seed: AppStoreScreenshotVariant.seed),
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.selectedRow = 4
            state.selectedCol = 4
            return state
        case .playing:
            let board = playingBoard()
            let state = GameState(
                board: board,
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.status = .playing
            state.elapsedTime = 94
            state.flagCount = board.flagCount
            state.selectedRow = 5
            state.selectedCol = 6
            return state
        case .complete:
            let state = GameState(
                board: completedBoard(),
                dailySeed: AppStoreScreenshotVariant.seed,
                puzzleType: .random
            )
            state.status = .won
            state.elapsedTime = 187
            state.flagCount = Board.mineCount
            state.selectedRow = 0
            state.selectedCol = 0
            return state
        }
    }

    private static func playingBoard() -> Board {
        var board = Board(seed: AppStoreScreenshotVariant.seed)
        board.clearAreaForOpening(centerRow: 4, centerCol: 4, seed: AppStoreScreenshotVariant.seed)

        for (row, col) in [(4, 4), (1, 6), (7, 2)] where !board.cells[row][col].hasMine {
            _ = board.reveal(row: row, col: col)
        }

        var flagsPlaced = 0
        for row in 0..<Board.rows {
            for col in 0..<Board.cols where board.cells[row][col].hasMine && flagsPlaced < 4 {
                board.toggleFlag(row: row, col: col)
                flagsPlaced += 1
            }
        }

        return board
    }

    private static func completedBoard() -> Board {
        let source = Board(seed: AppStoreScreenshotVariant.seed)
        var cells = source.cells

        for row in 0..<Board.rows {
            for col in 0..<Board.cols {
                if cells[row][col].hasMine {
                    cells[row][col].state = .flagged
                } else {
                    cells[row][col].state = .revealed(adjacentMines: source.adjacentMineCount(row: row, col: col))
                }
            }
        }

        return Board(cells: cells)
    }
}
#endif

/// Menu bar icon view showing state-specific icon with subtle indicators.
struct MenuBarIconView: View {
    let state: MenuBarIconState
    let elapsedTime: TimeInterval
    let currentStreak: Int

    private var baseIconName: String {
        switch state {
        case .normal, .complete:
            return "square.grid.3x3.fill"
        case .incomplete:
            return "square.grid.3x3"
        case .playing, .paused:
            return "square.grid.3x3.topleft.filled"
        case .lost:
            return "square.grid.3x3.bottomright.filled"
        }
    }

    private var overlayName: String? {
        state.overlaySymbol
    }

    private var accessibilityLabel: String {
        switch state {
        case .normal:
            return String(localized: "menu_bar_title")
        case .incomplete:
            return String(localized: "menu_bar_accessibility_incomplete")
        case .playing:
            return String(format: String(localized: "menu_bar_accessibility_playing"), formatTime(elapsedTime))
        case .paused:
            return String(format: String(localized: "menu_bar_accessibility_paused"), formatTime(elapsedTime))
        case .complete:
            return String(format: String(localized: "menu_bar_accessibility_complete"), currentStreak)
        case .lost:
            return String(localized: "menu_bar_accessibility_lost")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: baseIconName)

                if let overlayName {
                    Image(systemName: overlayName)
                        .font(.system(size: 7, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .offset(x: 5, y: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .frame(width: 22, alignment: .center)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
