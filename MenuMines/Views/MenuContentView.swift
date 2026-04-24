import SwiftUI
import AppKit

struct MenuContentView: View {
    var gameState: GameState

    @AppStorage(Constants.SettingsKeys.confirmBeforeReset) private var confirmBeforeReset = false
    @State private var showResetConfirmation = false
    @State private var showCelebration = false
    @State private var isFlagMode = false

    private var isGameComplete: Bool {
        gameState.status == .won || gameState.status == .lost
    }

    private let contentHeight: CGFloat = 372

    private func copyShareTextToClipboard() {
        let shareDate = gameState.puzzleType == .daily ? dateFromSeed(gameState.dailySeed) ?? Date() : Date()
        guard let text = gameState.shareText(for: shareDate) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func handleResetRequest() {
        // Prevent multiple reset requests while confirmation dialog is already showing
        guard !showResetConfirmation else { return }

        if confirmBeforeReset {
            showResetConfirmation = true
        } else {
            performReset()
        }
    }

    private func performReset() {
        gameState.reset()
    }

    private func announceGameResult(won: Bool) {
        let message: String
        if won {
            let seconds = Int(gameState.elapsedTime)
            if seconds == 1 {
                message = String(localized: "announcement_win_one_second")
            } else {
                message = String(format: String(localized: "announcement_win"), seconds)
            }
        } else {
            message = String(localized: "announcement_lose")
        }
        AccessibilityNotification.Announcement(message).post()
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 12) {
                HeaderView(
                    status: gameState.status,
                    elapsedTime: gameState.elapsedTime,
                    flagCount: gameState.flagCount,
                    canReset: gameState.canReset,
                    onReset: handleResetRequest
                )

                GameBoardView(
                    board: gameState.board,
                    gameStatus: gameState.status,
                    selectedRow: gameState.selectedRow,
                    selectedCol: gameState.selectedCol,
                    isFlagMode: isFlagMode,
                    onReveal: { row, col in
                        gameState.reveal(row: row, col: col)
                    },
                    onFlag: { row, col in
                        gameState.toggleFlag(row: row, col: col)
                    }
                )

                FooterView(
                    isGameComplete: isGameComplete,
                    puzzleType: gameState.puzzleType,
                    canReset: gameState.canReset,
                    isFlagMode: isFlagMode,
                    onReset: handleResetRequest,
                    onToggleFlagMode: {
                        isFlagMode.toggle()
                    },
                    onShare: {
                        copyShareTextToClipboard()
                    },
                    onAbout: {
                        AboutWindow.show()
                    }
                )
            }
            .padding()

            ConfettiView(isActive: showCelebration)

            // Inline reset confirmation overlay
            if showResetConfirmation {
                ResetConfirmationOverlay(
                    onCancel: {
                        showResetConfirmation = false
                    },
                    onConfirm: {
                        showResetConfirmation = false
                        performReset()
                    }
                )
            }
        }
        .frame(width: 300, height: contentHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            gameState.checkForDailyRollover()
            gameState.checkContinuousPlaySetting()
            gameState.resumeTimer()
        }
        .onDisappear {
            gameState.pauseTimer()
            gameState.save()
        }
        .onChange(of: gameState.status) { oldStatus, newStatus in
            switch newStatus {
            case .won:
                isFlagMode = false
                showCelebration = true
                announceGameResult(won: true)
                gameState.save()
            case .lost:
                isFlagMode = false
                announceGameResult(won: false)
                gameState.save()
            case .playing:
                // Clear celebration when resetting from won state
                if oldStatus == .won {
                    showCelebration = false
                }
            case .notStarted:
                // Clear celebration when resetting from won state
                if oldStatus == .won {
                    showCelebration = false
                }
            }
        }
    }
}

/// Inline confirmation overlay for reset action.
/// Uses an overlay instead of system alert to avoid MenuBarExtra dismissal issues.
private struct ResetConfirmationOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // Confirmation card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(String(localized: "reset_confirmation_title"))
                        .font(.headline)
                    Text(String(localized: "reset_confirmation_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 12) {
                    Button(String(localized: "reset_confirmation_cancel")) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(String(localized: "reset_confirmation_confirm")) {
                        onConfirm()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10)
            .accessibilityAddTraits(.isModal)
        }
    }
}

#Preview {
    MenuContentView(gameState: GameState(board: Board(seed: 12345)))
}
