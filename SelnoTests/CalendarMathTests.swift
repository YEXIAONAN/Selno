import Foundation
import Testing
@testable import Selno

@MainActor
struct CalendarMathTests {
    private func calendar(firstWeekday: Int = 2, zone: TimeZone = .gmt) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = zone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test func currentMonthAndSystemWeekdayOrderAreCorrect() throws {
        let calendar = Calendar.current
        let now = Date.now
        let window = CalendarMath.window(containing: now, mode: .month, listRange: .month, calendar: calendar)
        let month = try #require(calendar.dateInterval(of: .month, for: now))
        let monthDays = window.days.filter { $0 >= month.start && $0 < month.end }
        #expect(monthDays.count == calendar.range(of: .day, in: .month, for: now)?.count)
        #expect(window.days.count % 7 == 0)
        #expect(calendar.component(.weekday, from: try #require(window.days.first)) == calendar.firstWeekday)
        #expect(window.range.start <= month.start)
        #expect(window.range.end >= month.end)
    }

    @Test(arguments: [(2024, 29), (2025, 28), (2000, 29), (2100, 28)])
    func februaryRespectsLeapYearRules(yearAndDays: (Int, Int)) throws {
        let calendar = calendar()
        let february = try date(yearAndDays.0, 2, 15, calendar: calendar)
        let window = CalendarMath.window(containing: february, mode: .month, listRange: .month, calendar: calendar)
        let days = window.days.filter { calendar.isDate($0, equalTo: february, toGranularity: .month) }
        #expect(days.count == yearAndDays.1)
        #expect(calendar.component(.day, from: try #require(days.first)) == 1)
        #expect(calendar.component(.day, from: try #require(days.last)) == yearAndDays.1)
    }

    @Test func monthWeekYearAndListRangeNavigation() throws {
        let calendar = calendar()
        let december = try date(2025, 12, 15, calendar: calendar)
        let january = CalendarMath.moved(december, by: 1, mode: .month, listRange: .month, calendar: calendar)
        #expect(calendar.component(.year, from: january) == 2026)
        #expect(calendar.component(.month, from: january) == 1)
        #expect(CalendarMath.moved(january, by: -1, mode: .month, listRange: .month, calendar: calendar) == december)
        let nextWeek = CalendarMath.moved(december, by: 1, mode: .week, listRange: .month, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: december, to: nextWeek).day == 7)
        let year = try #require(calendar.date(byAdding: .year, value: 1, to: december))
        #expect(calendar.component(.year, from: year) == 2026)
        for mode in CalendarViewMode.allCases {
            let window = CalendarMath.window(containing: december, mode: mode, listRange: .month, calendar: calendar)
            #expect(window.range.start < window.range.end)
        }
        let week = CalendarMath.window(containing: december, mode: .list, listRange: .week, calendar: calendar)
        let month = CalendarMath.window(containing: december, mode: .list, listRange: .month, calendar: calendar)
        let thirty = CalendarMath.window(containing: december, mode: .list, listRange: .thirtyDays, calendar: calendar)
        #expect(week.days.count == 7)
        #expect(month.days.count == 31)
        #expect(thirty.days.count == 30)
    }

    @Test func firstWeekdayAndDSTUseCalendarArithmetic() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let monday = calendar(firstWeekday: 2, zone: zone)
        let sunday = calendar(firstWeekday: 1, zone: zone)
        let march = try date(2026, 3, 8, calendar: monday)
        let monWindow = CalendarMath.window(containing: march, mode: .week, listRange: .week, calendar: monday)
        let sunWindow = CalendarMath.window(containing: march, mode: .week, listRange: .week, calendar: sunday)
        #expect(monWindow.days.count == 7)
        #expect(sunWindow.days.count == 7)
        #expect(monWindow.range.start != sunWindow.range.start)
        let day = try #require(monday.dateInterval(of: .day, for: march))
        #expect(day.duration == 23 * 3600)
        let days = CalendarMath.days(in: sunWindow.range, calendar: sunday)
        #expect(Set(days.map { sunday.component(.weekday, from: $0) }).count == 7)
    }
}
