import SwiftUI

/// Window for displaying game statistics.
struct StatsWindow: View {
    @State private var showResetConfirmation = false
    @State private var selectedTab: StatsTab = .summary
    @AppStorage(Constants.SettingsKeys.showStreaks) private var showStreaks = true

    private var store: StatsStore {
        StatsStore.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Picker("", selection: $selectedTab) {
                ForEach(StatsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if store.hasResults {
                selectedContent
            } else {
                emptyStateSection
            }

            Divider()
            footerSection
        }
        .frame(width: 360)
        .fixedSize()
        .alert(String(localized: "stats_reset_confirmation_title"), isPresented: $showResetConfirmation) {
            Button(String(localized: "stats_reset_confirmation_cancel"), role: .cancel) {}
            Button(String(localized: "stats_reset_confirmation_confirm"), role: .destructive) {
                store.reset()
            }
        } message: {
            Text(String(localized: "stats_reset_confirmation_message"))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(String(localized: "stats_title"))
            .font(.title2)
            .fontWeight(.semibold)
            .padding()
    }

    // MARK: - Metrics

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .summary:
            summarySection
        case .history:
            historySection
        case .recent:
            recentSection
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            dailyMetricsSection

            Divider()
                .padding(.vertical, 4)

            allGamesMetricsSection
        }
        .padding()
    }

    private var historySection: some View {
        DailyCompletionCalendarView(resultsBySeed: store.dailyResultsBySeed)
            .padding()
    }

    @ViewBuilder
    private var recentSection: some View {
        if store.recentDailyResults.isEmpty {
            Text(String(localized: "stats_recent_empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
                .padding(.horizontal)
        } else {
            RecentDailyResultsView(results: store.recentDailyResults)
                .padding()
        }
    }

    private var dailyMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "stats_section_daily"))
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                metricRow(label: String(localized: "stats_games_played"), value: "\(store.dailyGamesPlayed)")
                metricRow(label: String(localized: "stats_wins"), value: "\(store.dailyWins)")
                metricRow(label: String(localized: "stats_win_rate"), value: formattedDailyWinRate)
                metricRow(label: String(localized: "stats_completion_rate"), value: formattedDailyCompletionRate)
                metricRow(label: String(localized: "stats_best_time"), value: formattedDailyBestTime)
                metricRow(label: String(localized: "stats_avg_time"), value: formattedDailyAverageTime)
                if showStreaks {
                    streaksRows
                }
            }
        }
    }

    private var allGamesMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "stats_section_all"))
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                metricRow(label: String(localized: "stats_games_played"), value: "\(store.gamesPlayed)")
                metricRow(label: String(localized: "stats_wins"), value: "\(store.wins)")
                metricRow(label: String(localized: "stats_win_rate"), value: formattedWinRate)
                metricRow(label: String(localized: "stats_best_time"), value: formattedBestTime)
                metricRow(label: String(localized: "stats_avg_time"), value: formattedAverageTime)
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "metric_accessibility_label"), label, value))
    }

    private var streaksRows: some View {
        Group {
            metricRow(label: String(localized: "stats_current_streak"), value: "\(store.currentStreak)")
            metricRow(label: String(localized: "stats_longest_streak"), value: "\(store.longestStreak)")
        }
    }

    private var formattedDailyWinRate: String {
        guard let rate = store.dailyWinRate else { return String(localized: "stats_no_data") }
        return "\(rate)%"
    }

    private var formattedWinRate: String {
        guard let rate = store.winRate else { return String(localized: "stats_no_data") }
        return "\(rate)%"
    }

    private var formattedDailyCompletionRate: String {
        guard let rate = store.dailyCompletionRate else { return String(localized: "stats_no_data") }
        return "\(rate)%"
    }

    private var formattedDailyBestTime: String {
        guard let time = store.dailyBestTime else { return String(localized: "stats_no_data") }
        return formatTime(time)
    }

    private var formattedDailyAverageTime: String {
        guard let time = store.dailyAverageTime else { return String(localized: "stats_no_data") }
        return formatTime(time)
    }

    private var formattedBestTime: String {
        guard let time = store.bestTime else { return String(localized: "stats_no_data") }
        return formatTime(time)
    }

    private var formattedAverageTime: String {
        guard let time = store.averageTime else { return String(localized: "stats_no_data") }
        return formatTime(time)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(String(localized: "stats_empty_message"))
                    .font(.headline)
                Text(String(localized: "stats_empty_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showStreaks {
                VStack(spacing: 12) {
                    streaksRows
                }
                .padding(.top, 8)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trackedSince = store.trackedSince {
                Text(String(format: String(localized: "stats_tracked_since"), formattedDate(trackedSince)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button(String(localized: "stats_reset_button")) {
                showResetConfirmation = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption)
            .accessibilityHint(String(localized: "stats_reset_accessibility_hint"))
        }
        .padding()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private enum StatsTab: String, CaseIterable, Identifiable {
    case summary
    case history
    case recent

    var id: Self { self }

    var title: String {
        switch self {
        case .summary:
            return String(localized: "stats_tab_summary")
        case .history:
            return String(localized: "stats_tab_history")
        case .recent:
            return String(localized: "stats_tab_recent")
        }
    }
}

// MARK: - Daily Completion Calendar

private struct DailyCompletionCalendarView: View {
    let resultsBySeed: [Int64: GameResult]

    @State private var displayedMonth = Self.currentMonthStart()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private static func currentMonthStart() -> Date {
        let calendar = Self.calendar
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "stats_calendar_title"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "stats_calendar_previous_month"))

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isShowingCurrentOrFutureMonth)
                .accessibilityLabel(String(localized: "stats_calendar_next_month"))
            }

            Text(monthTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .accessibilityLabel(String(format: String(localized: "stats_calendar_month_accessibility"), monthTitle))

            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(calendarCells) { cell in
                    CalendarDayCell(cell: cell, result: result(for: cell))
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.timeZone = .gmt
        formatter.locale = .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }

        let firstIndex = Self.calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var isShowingCurrentOrFutureMonth: Bool {
        Self.calendar.compare(displayedMonth, to: Self.currentMonthStart(), toGranularity: .month) != .orderedAscending
    }

    private var calendarCells: [CalendarCell] {
        let calendar = Self.calendar
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingEmptyCells = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<leadingEmptyCells).map { CalendarCell(id: "empty-\($0)", date: nil, day: nil) }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth) else { continue }
            cells.append(CalendarCell(id: "day-\(seedFromDate(date))", date: date, day: day))
        }

        return cells
    }

    private func result(for cell: CalendarCell) -> GameResult? {
        guard let date = cell.date else { return nil }
        return resultsBySeed[seedFromDate(date)]
    }

    private func moveMonth(by value: Int) {
        guard let month = Self.calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = month
    }
}

private struct CalendarCell: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
}

private struct CalendarDayCell: View {
    let cell: CalendarCell
    let result: GameResult?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: 1)
                )

            if let day = cell.day {
                Text("\(day)")
                    .font(.caption2)
                    .fontWeight(result == nil ? .regular : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHidden(cell.date == nil)
    }

    private var fillColor: Color {
        guard let result else {
            return Color(nsColor: .controlBackgroundColor)
        }
        return result.won ? Color.accentColor.opacity(0.28) : Color.red.opacity(0.24)
    }

    private var borderColor: Color {
        guard let result else {
            return Color(nsColor: .separatorColor).opacity(0.7)
        }
        return result.won ? Color.accentColor.opacity(0.65) : Color.red.opacity(0.55)
    }

    private var textColor: Color {
        result == nil ? .secondary : .primary
    }

    private var accessibilityLabel: String {
        guard let date = cell.date else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: date)

        guard let result else {
            return String(format: String(localized: "stats_calendar_day_not_played"), dateString)
        }
        if result.won {
            return String(format: String(localized: "stats_calendar_day_won"), dateString)
        }
        return String(format: String(localized: "stats_calendar_day_lost"), dateString)
    }
}

// MARK: - Recent Daily Results

private struct RecentDailyResultsView: View {
    let results: [GameResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "stats_recent_title"))
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ForEach(results, id: \.dailySeed) { result in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(result.won ? Color.accentColor : Color.red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)

                        Text(formattedDate(forSeed: result.dailySeed))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(result.won ? String(localized: "stats_result_won") : String(localized: "stats_result_lost"))
                            .foregroundStyle(.secondary)

                        Text(formatTime(result.elapsedTime))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: result))
                }
            }
        }
    }

    private func formattedDate(forSeed seed: Int64) -> String {
        guard let date = dateFromSeed(seed) else { return "\(seed)" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func accessibilityLabel(for result: GameResult) -> String {
        let status = result.won ? String(localized: "stats_result_won") : String(localized: "stats_result_lost")
        return String(
            format: String(localized: "stats_recent_accessibility_label"),
            formattedDate(forSeed: result.dailySeed),
            status,
            formatTime(result.elapsedTime)
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Previews

#Preview("Stats - Empty") {
    StatsWindow()
}
