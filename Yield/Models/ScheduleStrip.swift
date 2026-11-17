import Foundation

/// One day's meetings as a horizontal line: where each sits between
/// the first hour and the last, which lane it takes when two overlap,
/// and — today — where "now" falls. Pure layout: fractions of the
/// strip's width, so the view only multiplies. Built by the view model
/// for the day selected in the weekday bar, and tested without
/// rendering.
struct ScheduleStrip: Equatable {
    /// Only today has a past and a present: every meeting on another
    /// day is `upcoming`, drawn at the one strength.
    enum Phase: Equatable {
        case past
        case current
        case upcoming
    }

    struct Block: Identifiable, Equatable {
        let event: CalendarEvent
        /// Leading edge and width, as fractions of the strip (0…1).
        let start: Double
        let width: Double
        /// 0 for the top lane; overlapping meetings take the next down.
        let lane: Int
        let phase: Phase
        var id: String { event.id }
    }

    /// The start of an hour column. The strip's closing hour has no
    /// mark: it is the right-hand edge.
    struct HourMark: Equatable {
        let fraction: Double
        let label: String
    }

    /// The strip always covers the working day, so a meeting's place on
    /// it means the same thing every day; meetings outside these hours
    /// stretch it rather than fall off it.
    static let workdayStartHour = 9
    static let workdayEndHour = 17

    let blocks: [Block]
    let laneCount: Int
    let hourMarks: [HourMark]
    /// Nil on any day but today, and outside the strip's hours.
    let nowFraction: Double?
    /// False while the day's events are still being fetched, so an
    /// empty strip isn't read as an empty day.
    let isLoaded: Bool
    /// The day drawn is today.
    let showsToday: Bool

    /// - Parameters:
    ///   - events: the day's events, or nil when they aren't known yet.
    ///   - day: any moment on the day being drawn.
    init(events: [CalendarEvent]?, day: Date, now: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86400)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        showsToday = isToday
        isLoaded = events != nil
        // A cache fetched just before midnight may briefly hold the
        // day before's.
        let onDay = (events ?? []).filter { $0.start < dayEnd && $0.end > dayStart && $0.end > $0.start }

        func hour(_ h: Int) -> Date {
            calendar.date(bySettingHour: h, minute: 0, second: 0, of: dayStart)
                ?? dayStart.addingTimeInterval(Double(h) * 3600)
        }
        let workStart = hour(Self.workdayStartHour)
        let workEnd = hour(Self.workdayEndHour)
        let earliest = max(dayStart, min(onDay.map(\.start).min() ?? workStart, workStart))
        let latest = min(dayEnd, max(onDay.map(\.end).max() ?? workEnd, workEnd))
        let rangeStart = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let hours = max(1, Int(ceil(latest.timeIntervalSince(rangeStart) / 3600)))
        let span = Double(hours) * 3600

        func fraction(_ date: Date) -> Double {
            min(1, max(0, date.timeIntervalSince(rangeStart) / span))
        }

        // Lanes are the day view's columns turned on their side.
        let placed = DayTimeline(events: onDay, calendar: calendar).blocks
        blocks = placed.map { placed in
            let event = placed.event
            let start = fraction(event.start)
            let phase: Phase = !isToday || event.start > now ? .upcoming : (event.end <= now ? .past : .current)
            return Block(
                event: event, start: start, width: fraction(event.end) - start,
                lane: placed.column, phase: phase
            )
        }
        laneCount = (placed.map(\.column).max() ?? 0) + 1
        hourMarks = (0..<hours).map { index in
            let date = rangeStart.addingTimeInterval(Double(index) * 3600)
            // "9am 10 11 12pm 1 2": the first hour and noon carry the
            // am/pm, and the rest are read from them.
            let hour = calendar.component(.hour, from: date)
            let label = (index == 0 || hour % 12 == 0)
                ? DayTimeline.hourLabel(for: date)
                : String((hour + 11) % 12 + 1)
            return HourMark(fraction: Double(index) / Double(hours), label: label)
        }
        let nowOffset = now.timeIntervalSince(rangeStart)
        nowFraction = isToday && (0...span).contains(nowOffset) ? nowOffset / span : nil
    }
}
