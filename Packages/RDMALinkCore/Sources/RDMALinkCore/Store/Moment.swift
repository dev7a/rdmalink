import Foundation

/// How a moment is written in the copy that quotes one — the Restore sheet's
/// "exactly as it was on 3 September at 14:21" (UX_SPEC §7.1) and the change
/// log's notes (§S11, `ChangeSentence`).
///
/// The day is the locale's own long day-and-month; the time is **the
/// locale's short time** — `14:21`, or `2:21 PM` where the locale keeps a
/// 12-hour clock — and never a 12-hour hour without its AM/PM. The old
/// `.twoDigits(amPM: .omitted)` printed "02:48" for 14:48 on an `en_US` Mac,
/// which reads as ten to three in the morning.
///
/// Public because the app's own two joins — `3 September at 14:21` inside a
/// sentence and `3 September, 14:21` at the head of a change-log entry — take
/// their halves from here, so a time is never formatted two ways.
public enum Moment {
    public static func text(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        "\(day(date, locale: locale)) at \(time(date, locale: locale))"
    }

    /// "3 September" in `en_GB`, "September 3" in `en_US`, "3. September" in
    /// `de_DE`: the day-and-month the spec's examples are shaped on.
    public static func day(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.locale(locale).day().month(.wide))
    }

    /// The locale's short time. `hour()` defaults to the locale's own clock
    /// and keeps the day period where that clock is a 12-hour one.
    public static func time(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.locale(locale).hour().minute())
    }
}
