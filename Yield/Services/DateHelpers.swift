import Foundation

enum DateHelpers {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

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
        let bounds = currentWeekBounds()
        let calendar = Calendar.current
        let startStr = displayFormatter.string(from: bounds.start)
        let endStr = displayFormatter.string(from: bounds.end)
        let year = calendar.component(.year, from: bounds.start)
        return "\(startStr) – \(endStr), \(year)"
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
