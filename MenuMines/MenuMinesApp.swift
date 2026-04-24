import AppKit
import Sentry
import SwiftUI

@main
struct MenuMinesApp: App {
    @State private var gameState: GameState
    @AppStorage(Constants.SettingsKeys.showMenuBarIndicators) private var showMenuBarIndicators = true

    private static var eventMonitor: Any?

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

        let state = GameState.restored()
        _gameState = State(initialValue: state)
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
