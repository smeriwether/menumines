import AppKit
import SwiftUI

struct CellView: View {
    let cell: Cell
    let row: Int
    let col: Int
    let gameStatus: GameStatus
    let isSelected: Bool
    let onReveal: () -> Void
    let onFlag: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private static let cellSize: CGFloat = 28

    var body: some View {
        ZStack {
            background
            hoverOverlay
            content
        }
        .frame(width: Self.cellSize, height: Self.cellSize)
        .overlay(selectionBorder)
        .overlay(
            ClickHandlerView(onLeftClick: onReveal, onRightClick: onFlag)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(accessibilityTraits)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if cell.isExploded {
            return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_exploded_mine"))
        }

        switch cell.state {
        case .hidden:
            return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_covered"))
        case .flagged:
            return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_flagged"))
        case .revealed(let adjacentMines):
            if cell.hasMine {
                return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_mine"))
            } else if adjacentMines == 0 {
                return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_empty"))
            } else if adjacentMines == 1 {
                return formattedAccessibilityLabel(stateDescription: String(localized: "cell_state_one_mine"))
            } else {
                return formattedAccessibilityLabel(
                    stateDescription: String(format: String(localized: "cell_state_mines"), adjacentMines)
                )
            }
        }
    }

    private func formattedAccessibilityLabel(stateDescription: String) -> String {
        String(
            format: String(localized: "cell_accessibility_label"),
            row + 1,
            col + 1,
            stateDescription
        )
    }

    private var accessibilityHint: String {
        guard gameStatus == .notStarted || gameStatus == .playing else {
            return ""
        }

        switch cell.state {
        case .hidden:
            return String(localized: "cell_hint_reveal_or_flag")
        case .flagged:
            return String(localized: "cell_hint_remove_flag")
        case .revealed:
            return ""
        }
    }

    private var accessibilityTraits: AccessibilityTraits {
        switch cell.state {
        case .hidden, .flagged:
            return .isButton
        case .revealed:
            return .isStaticText
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if cell.isExploded {
            Color.red
        } else if case .revealed = cell.state {
            revealedBackground
        } else {
            RaisedCellBackground(colorScheme: colorScheme)
        }
    }

    private var revealedBackground: Color {
        if colorScheme == .dark {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color(nsColor: .controlBackgroundColor).opacity(0.6)
        }
    }

    // MARK: - Hover

    private var isRevealed: Bool {
        if case .revealed = cell.state { return true }
        return false
    }

    @ViewBuilder
    private var hoverOverlay: some View {
        if isHovered && !isRevealed && !cell.isExploded {
            if colorScheme == .dark {
                Color.white.opacity(0.15)
            } else {
                Color.black.opacity(0.1)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if cell.isExploded {
            mineIcon
        } else {
            switch cell.state {
            case .hidden:
                EmptyView()
            case .flagged:
                Text("🚩")
                    .font(.system(size: 14))
            case .revealed(let adjacentMines):
                if cell.hasMine {
                    mineIcon
                } else if adjacentMines > 0 {
                    Text("\(adjacentMines)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(color(for: adjacentMines))
                }
            }
        }
    }

    private var mineIcon: some View {
        Text("💣")
            .font(.system(size: 14))
    }

    // MARK: - Selection Border

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 2)
        }
    }

    // MARK: - Number Colors
    // Classic Minesweeper palette with adaptive colors for light/dark mode.
    // Dark mode uses brighter variants for readability on dark backgrounds.

    private func color(for adjacentMines: Int) -> Color {
        let isDark = colorScheme == .dark

        switch adjacentMines {
        case 1: // Blue
            return isDark
                ? Color(red: 0.4, green: 0.6, blue: 1.0)
                : Color(red: 0.0, green: 0.0, blue: 1.0)
        case 2: // Green
            return isDark
                ? Color(red: 0.4, green: 0.85, blue: 0.4)
                : Color(red: 0.0, green: 0.5, blue: 0.0)
        case 3: // Red
            return isDark
                ? Color(red: 1.0, green: 0.4, blue: 0.4)
                : Color(red: 0.8, green: 0.0, blue: 0.0)
        case 4: // Navy
            return isDark
                ? Color(red: 0.5, green: 0.5, blue: 1.0)
                : Color(red: 0.0, green: 0.0, blue: 0.55)
        case 5: // Brown
            return isDark
                ? Color(red: 0.9, green: 0.6, blue: 0.3)
                : Color(red: 0.55, green: 0.27, blue: 0.07)
        case 6: // Teal
            return isDark
                ? Color(red: 0.4, green: 0.9, blue: 0.9)
                : Color(red: 0.0, green: 0.55, blue: 0.55)
        case 7: // Gray (dark in light mode, light in dark mode)
            return isDark
                ? Color(red: 0.75, green: 0.75, blue: 0.75)
                : Color(red: 0.2, green: 0.2, blue: 0.2)
        case 8: // Gray (medium in light mode, lighter in dark mode)
            return isDark
                ? Color(red: 0.85, green: 0.85, blue: 0.85)
                : Color(red: 0.5, green: 0.5, blue: 0.5)
        default:
            return .primary
        }
    }
}

// MARK: - Click Handler

private struct ClickHandlerView: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let view = ClickableNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

private class ClickableNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            // Control+Click is the macOS convention for secondary click
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

// MARK: - Raised Cell Background

private struct RaisedCellBackground: View {
    let colorScheme: ColorScheme
    private let bevelWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            let inset = bevelWidth
            let highlightOpacity: Double = colorScheme == .dark ? 0.3 : 0.5
            let shadowOpacity: Double = colorScheme == .dark ? 0.5 : 0.3

            ZStack {
                Color(nsColor: .controlColor)

                // Top and left highlight
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(highlightOpacity))

                // Bottom and right shadow
                Path { path in
                    path.move(to: CGPoint(x: size, y: 0))
                    path.addLine(to: CGPoint(x: size, y: size))
                    path.addLine(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(shadowOpacity))
            }
        }
    }
}

// MARK: - Previews

#Preview("Hidden Cell") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Hidden Cell (Selected)") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: true,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Revealed - Zero") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Revealed - Numbers") {
    HStack(spacing: 2) {
        ForEach(1...8, id: \.self) { count in
            CellView(
                cell: Cell(state: .revealed(adjacentMines: count), hasMine: false),
                row: 0,
                col: count - 1,
                gameStatus: .playing,
                isSelected: false,
                onReveal: {},
                onFlag: {}
            )
        }
    }
    .padding()
}

#Preview("Flagged Cell") {
    CellView(
        cell: Cell(state: .flagged, hasMine: true),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Mine (Game Over)") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: true),
        row: 0,
        col: 0,
        gameStatus: .lost,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

#Preview("Exploded Mine") {
    CellView(
        cell: Cell(state: .revealed(adjacentMines: 0), hasMine: true, isExploded: true),
        row: 0,
        col: 0,
        gameStatus: .lost,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
}

// MARK: - Dark Mode Previews

#Preview("Hidden Cell (Dark)") {
    CellView(
        cell: Cell(state: .hidden, hasMine: false),
        row: 0,
        col: 0,
        gameStatus: .playing,
        isSelected: false,
        onReveal: {},
        onFlag: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Revealed - Numbers (Dark)") {
    HStack(spacing: 2) {
        ForEach(1...8, id: \.self) { count in
            CellView(
                cell: Cell(state: .revealed(adjacentMines: count), hasMine: false),
                row: 0,
                col: count - 1,
                gameStatus: .playing,
                isSelected: false,
                onReveal: {},
                onFlag: {}
            )
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
