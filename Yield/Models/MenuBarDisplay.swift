import Foundation

/// Which graphic the menu bar item draws. Independent of
/// `MenuBarLabelMode`, which picks the text beside it. Persisted to
/// UserDefaults via the `menuBarStyle` key.
enum MenuBarStyle: String, CaseIterable {
    /// The original display: a monochrome SF Symbol (gauge needle,
    /// calendar, pause…) plus the label. Rendered as a template image,
    /// so macOS colors it. The default, and unchanged by the other
    /// styles existing.
    case classic
    /// A ring that fills toward the running project's booking, tinted
    /// by budget health.
    case ring
    /// A filled capsule holding the label; the fill color is the
    /// budget health and doubles as a progress bar.
    case capsule
    /// Five bars, Monday to Friday, each filling toward the daily
    /// target. Today's bar grows live.
    case weekBars

    static let `default`: MenuBarStyle = .classic

    var label: String {
        switch self {
        case .classic:  return "Classic"
        case .ring:     return "Budget ring"
        case .capsule:  return "Status capsule"
        case .weekBars: return "Week bars"
        }
    }
}

/// Everything the non-classic menu bar styles need to draw, as plain
/// values. Built by `TimeComparisonViewModel.menuBarGraphicState` and
/// consumed by `MenuBarGraphicRenderer`, so the drawing code never
/// reaches into the view model and the state logic is testable
/// without rendering.
struct MenuBarGraphicState: Equatable {
    enum TimerState: Equatable {
        case none, running, paused
    }

    /// Budget health of the running timer's project. Only a running
    /// timer on a booked project is ever anything but `.neutral`:
    /// color in the menu bar means "the clock is running", and the
    /// hue says how the booking is holding up.
    enum Tone: Equatable {
        case neutral, onPace, nearLimit, over
    }

    var timer: TimerState = .none
    var tone: Tone = .neutral
    /// 0...1. With a timer set: tracked / booked on its project, nil
    /// when that project has no booking to measure against. With no
    /// timer: the week's tracked hours against the weekly budget.
    var progress: Double? = nil
    /// Full day of time off today and no timer set.
    var isTimeOff = false
    /// The data on screen may be out of date (API or connectivity
    /// error). Draws dimmed and dashed.
    var isStale = false
    /// A calendar meeting is in its prompt window, waiting to be
    /// logged.
    var meetingDue = false
    /// The running timer is tied to a meeting — started from one and
    /// still on its entry.
    var meetingTimerRunning = false

    /// The meeting dot on the graphic: a meeting wants a timer, or has
    /// one. The dot, not coloured text, is the menu bar's meeting
    /// signal — a small solid shape holds up on a translucent bar
    /// where tinted text doesn't.
    var showsMeetingBadge: Bool { meetingDue || meetingTimerRunning }
    /// Monday…Friday, each day's logged hours as a 0...1 fraction of
    /// the daily target.
    var weekFractions: [Double] = []
    /// Index into `weekFractions` for today; nil on weekends.
    var todayIndex: Int? = nil

    /// Share of the booking at which a running timer turns from
    /// on-pace to nearly-out.
    static let nearLimitThreshold = 0.85

    /// Classify a running timer's project. "Over" matches the classic
    /// gauge's rule (strictly more logged than booked) so the two
    /// styles never disagree about the same project.
    static func tone(logged: Double, booked: Double) -> Tone {
        guard booked > 0 else { return .neutral }
        if logged > booked { return .over }
        if logged / booked >= nearLimitThreshold { return .nearLimit }
        return .onPace
    }

    /// Snap a fraction to a grid fine enough to be invisible at menu
    /// bar size. The state is part of the image cache key, so raw
    /// doubles that drift by a hair every tick would defeat the cache.
    static func quantize(_ value: Double) -> Double {
        (min(max(value, 0), 1) * 200).rounded() / 200
    }
}
