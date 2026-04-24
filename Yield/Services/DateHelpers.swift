import Foundation

enum DateHelpers {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// Short weekday labels, Monday-first. Used everywhere we need to label
    /// day-of-week cells (chart axis, weekday mini-bar, time-off breakdown).
    static let weekdayLabels: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Day of month, no leading zero — e.g. "3", "27".
    private static let dayOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// Short month + day — e.g. "Apr 27".
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Short month + day + year — e.g. "Apr 27, 2026".
    private static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// Build the seven (date, YYYY-MM-DD) pairs for a week starting at
    /// `weekStart`. Used anywhere we need to iterate a week's days in
    /// order and look up entries by date string. Force-unwraps the
    /// per-day `calendar.date(byAdding:)` calls because `(0..<7)` with a
    /// Gregorian calendar can't fail — silently dropping days would
    /// produce off-by-one rendering with no signal.
    static func weekDays(starting weekStart: Date) -> [(date: Date, str: String)] {
        let calendar = Calendar.current
        return (0..<7).map { i in
            guard let day = calendar.date(byAdding: .day, value: i, to: weekStart) else {
                preconditionFailure("calendar.date(byAdding:) failed for offset \(i)")
            }
            return (day, dateFormatter.string(from: day))
        }
    }

    static func currentWeekBounds() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = Date()
        // Find Monday of current week (weekday 2 in gregorian)
        let weekday = calendar.component(.weekday, from: today)
        // Sunday=1, Monday=2, ..., Saturday=7
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return (today, today)
        }
        let startOfMonday = calendar.startOfDay(for: monday)
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: startOfMonday) else {
            return (startOfMonday, startOfMonday)
        }
        return (startOfMonday, sunday)
    }

    static func weekDateStrings() -> (start: String, end: String) {
        let bounds = currentWeekBounds()
        return (dateFormatter.string(from: bounds.start), dateFormatter.string(from: bounds.end))
    }

    static func formattedWeekRange() -> String {
        formatWeekRange(bounds: currentWeekBounds())
    }

    /// Compact American week range format:
    ///   Same month:       "Apr 20 – 26, 2026"
    ///   Crosses months:   "Apr 27 – May 3, 2026"
    ///   Crosses year:     "Dec 29, 2025 – Jan 4, 2026"
    static func formatWeekRange(bounds: (start: Date, end: Date)) -> String {
        let calendar = Calendar.current
        let startMonth = calendar.component(.month, from: bounds.start)
        let endMonth = calendar.component(.month, from: bounds.end)
        let startYear = calendar.component(.year, from: bounds.start)
        let endYear = calendar.component(.year, from: bounds.end)

        if startYear != endYear {
            // Full, explicit on both ends when the year flips.
            let startFull = monthDayYearFormatter.string(from: bounds.start)
            let endFull = monthDayYearFormatter.string(from: bounds.end)
            return "\(startFull) – \(endFull)"
        }
        if startMonth != endMonth {
            let startMD = monthDayFormatter.string(from: bounds.start)
            let endMD = monthDayFormatter.string(from: bounds.end)
            let year = startYear
            return "\(startMD) – \(endMD), \(year)"
        }
        // Same month: show month once on the left, day range, year on the right.
        let startMD = monthDayFormatter.string(from: bounds.start)
        let endDay = dayOnlyFormatter.string(from: bounds.end)
        return "\(startMD) – \(endDay), \(startYear)"
    }

    /// Week bounds for the week at `offset` weeks from the current week.
    /// 0 = current week, -1 = last week, +1 = next week, etc.
    static func weekBounds(offset: Int) -> (start: Date, end: Date) {
        let current = currentWeekBounds()
        guard offset != 0,
              let start = Calendar.current.date(byAdding: .day, value: offset * 7, to: current.start),
              let end = Calendar.current.date(byAdding: .day, value: offset * 7, to: current.end)
        else { return current }
        return (start, end)
    }

    /// Formatted week range label for an arbitrary week offset.
    static func formattedWeekRange(offset: Int) -> String {
        formatWeekRange(bounds: weekBounds(offset: offset))
    }

    /// Count weekdays (Mon-Fri) where an assignment overlaps with the current week
    static func countOverlappingWeekdays(
        assignmentStart: String,
        assignmentEnd: String,
        weekStart: Date,
        weekEnd: Date
    ) -> Int {
        guard let aStart = dateFormatter.date(from: assignmentStart),
              let aEnd = dateFormatter.date(from: assignmentEnd) else {
            return 0
        }

        let calendar = Calendar.current

        // Clamp to week bounds
        let clampedStart = max(aStart, calendar.startOfDay(for: weekStart))
        let clampedEnd = min(aEnd, calendar.startOfDay(for: weekEnd))

        guard clampedStart <= clampedEnd else { return 0 }

        var count = 0
        var current = clampedStart
        while current <= clampedEnd {
            if !calendar.isDateInWeekend(current) {
                count += 1
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }
        return count
    }
}
