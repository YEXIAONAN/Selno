import Foundation

nonisolated enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month, week, list
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "月"
        case .week: "周"
        case .list: "列表"
        }
    }
}

nonisolated enum CalendarListRange: String, CaseIterable, Identifiable {
    case week, month, thirtyDays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "一周"
        case .month: "一个月"
        case .thirtyDays: "30 天"
        }
    }
}

nonisolated struct CalendarWindow: Hashable {
    let range: DateInterval
    let days: [Date]
}

nonisolated enum CalendarMath {
    static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }

    static func window(containing date: Date, mode: CalendarViewMode, listRange: CalendarListRange, calendar: Calendar) -> CalendarWindow {
        let day = calendar.startOfDay(for: date)
        let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let fallback = DateInterval(start: day, end: fallbackEnd)
        let interval: DateInterval
        switch mode {
        case .month:
            let month = calendar.dateInterval(of: .month, for: date) ?? fallback
            let start = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start ?? month.start
            let last = calendar.date(byAdding: .second, value: -1, to: month.end) ?? month.start
            let end = calendar.dateInterval(of: .weekOfYear, for: last)?.end ?? month.end
            interval = DateInterval(start: start, end: end)
        case .week:
            interval = calendar.dateInterval(of: .weekOfYear, for: date) ?? fallback
        case .list:
            switch listRange {
            case .week: interval = calendar.dateInterval(of: .weekOfYear, for: date) ?? fallback
            case .month: interval = calendar.dateInterval(of: .month, for: date) ?? fallback
            case .thirtyDays:
                interval = DateInterval(start: day, end: calendar.date(byAdding: .day, value: 30, to: day) ?? fallbackEnd)
            }
        }
        return CalendarWindow(range: interval, days: days(in: interval, calendar: calendar))
    }

    static func moved(_ date: Date, by offset: Int, mode: CalendarViewMode, listRange: CalendarListRange, calendar: Calendar) -> Date {
        let component: Calendar.Component
        let value: Int
        switch mode {
        case .month: component = .month; value = offset
        case .week: component = .weekOfYear; value = offset
        case .list:
            switch listRange {
            case .week: component = .weekOfYear; value = offset
            case .month: component = .month; value = offset
            case .thirtyDays: component = .day; value = 30 * offset
            }
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    static func defaultTime(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? calendar.startOfDay(for: day)
    }

    static func dayID(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.isLeapMonth == true ? 1 : 0)"
    }

    static func fullDate(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.wide).day().weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = Locale(identifier: "zh_Hans_CN")
        return date.formatted(style)
    }

    static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = Locale(identifier: "zh_Hans_CN")
        return date.formatted(style)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = Locale(identifier: "zh_Hans_CN")
        return date.formatted(style)
    }
}
