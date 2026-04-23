import SwiftUI

/// Window for displaying game statistics.
struct StatsWindow: View {
    @State private var showResetConfirmation = false
    @AppStorage(Constants.SettingsKeys.showStreaks) private var showStreaks = true

    private var store: StatsStore {
        StatsStore.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()

            if store.hasResults {
                metricsSection
            } else {
                emptyStateSection
            }

            Divider()
            footerSection
        }
        .frame(width: 380)
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

    private var metricsSection: some View {
        VStack(spacing: 16) {
            DailyCompletionCalendarView(dailyResultsBySeed: store.dailyResultsBySeed)

            Divider()
                .padding(.vertical, 4)

            // Daily Puzzles Section
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "stats_section_daily"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(spacing: 10) {
                    metricRow(label: String(localized: "stats_games_played"), value: "\(store.dailyGamesPlayed)")
                    metricRow(label: String(localized: "stats_wins"), value: "\(store.dailyWins)")
                    metricRow(label: String(localized: "stats_win_rate"), value: formattedDailyWinRate)
                    if showStreaks {
                        streaksRows
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // All Games Section
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
        .padding()
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
        .accessibilityLabel("\(label): \(value)")
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

// MARK: - Daily Completion Calendar

private struct DailyCompletionCalendarView: View {
    let dailyResultsBySeed: [Int64: GameResult]

    @State private var displayedMonth = Self.monthStart(for: Date())

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private var calendar: Calendar {
        Self.utcCalendar
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMM yyyy", options: 0, locale: .current) ?? "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return [] }

        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
        }

        return Array(repeating: nil, count: leadingEmptyDays) + days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "stats_calendar_title"))
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "stats_calendar_previous_month"))

                    Text(monthTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(minWidth: 120)
                        .accessibilityLabel(String(format: String(localized: "stats_calendar_month_accessibility"), monthTitle))

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "stats_calendar_next_month"))
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 14)
                        .accessibilityHidden(true)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayBox(
                            date: date,
                            result: dailyResultsBySeed[seedFromDate(date)],
                            calendar: calendar
                        )
                    } else {
                        Color.clear
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func monthStart(for date: Date) -> Date {
        let calendar = utcCalendar
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func moveMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else {
            return
        }
        displayedMonth = Self.monthStart(for: newMonth)
    }
}

private struct CalendarDayBox: View {
    let date: Date
    let result: GameResult?
    let calendar: Calendar

    private var dayNumber: Int {
        calendar.component(.day, from: date)
    }

    private var fillColor: Color {
        guard let result else { return Color(nsColor: .separatorColor).opacity(0.25) }
        return result.won ? .accentColor : .red
    }

    private var foregroundColor: Color {
        result == nil ? .secondary : .white
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        let dateString = formatter.string(from: date)

        guard let result else {
            return String(format: String(localized: "stats_calendar_day_not_played"), dateString)
        }

        if result.won {
            return String(format: String(localized: "stats_calendar_day_won"), dateString)
        } else {
            return String(format: String(localized: "stats_calendar_day_lost"), dateString)
        }
    }

    var body: some View {
        Text(dayNumber.formatted())
            .font(.caption2)
            .fontWeight(result == nil ? .regular : .semibold)
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
            .frame(width: 24, height: 24)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Previews

#Preview("Stats - Empty") {
    StatsWindow()
}
