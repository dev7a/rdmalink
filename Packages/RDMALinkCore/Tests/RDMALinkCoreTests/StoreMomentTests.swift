import Foundation
import Testing
@testable import RDMALinkCore

/// UX_SPEC §7.1: "Times are the user's locale's short time — 14:21, or
/// 2:21 PM where the locale keeps a 12-hour clock — never a 12-hour hour
/// without its AM/PM."
@Suite("Moment")
struct StoreMomentTests {
    /// A wall-clock time in the zone the string is read in: `Moment` formats
    /// in the process's own time zone, which is the user's, so the test
    /// builds its dates there too and the assertion holds on any Mac.
    private static func date(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private static func locale(_ identifier: String) -> Locale {
        Locale(identifier: identifier)
    }

    /// 20 September 2026, 14:48 — the time the bug printed as "02:48".
    private static let afternoon = date(day: 20, hour: 14, minute: 48)

    @Test("A 12-hour locale keeps its AM/PM")
    func twelveHourClockKeepsItsPeriod() {
        // Foundation sets the day period off with a narrow no-break space
        // (U+202F), so "2:48 PM" is spelled with that character here.
        let text = Moment.text(Self.afternoon, locale: Self.locale("en_US"))
        #expect(text == "September 20 at 2:48\u{202F}PM")
        #expect(Moment.time(Self.afternoon, locale: Self.locale("en_US")) == "2:48\u{202F}PM")
        // The shape the bug printed: a 12-hour hour with no period at all.
        #expect(!text.contains("02:48"))
    }

    @Test("A 24-hour locale prints the hour whole")
    func twentyFourHourClock() {
        #expect(Moment.text(Self.afternoon, locale: Self.locale("en_GB"))
                == "20 September at 14:48")
        #expect(Moment.text(Self.afternoon, locale: Self.locale("de_DE"))
                == "20. September at 14:48")
        #expect(Moment.time(Self.afternoon, locale: Self.locale("fr_FR")) == "14:48")
    }

    @Test("The spec's own example, in the locale it is shaped on")
    func specExample() {
        let date = Self.date(day: 3, hour: 14, minute: 21)
        #expect(Moment.text(date, locale: Self.locale("en_GB")) == "3 September at 14:21")
        #expect(ChangeSentence.alreadyPutBack(moment: Moment.text(date, locale: Self.locale("en_GB")))
                == "Already put back on 3 September at 14:21.")
    }
}
