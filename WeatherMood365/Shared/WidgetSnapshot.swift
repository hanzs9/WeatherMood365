import Foundation

enum WidgetSharedStore {
    static let appGroupIdentifier = "group.com.han.WeatherMood365"
    static let snapshotFilename = "widget-snapshot.json"
    static let latestImageFilename = "widget-latest.jpg"
    static let todayImageFilename = "widget-today.jpg"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFilename)
    }

    static func imageURL(named filename: String) -> URL? {
        containerURL?.appendingPathComponent(filename)
    }
}

struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var today: WidgetEntrySummary?
    var latest: WidgetEntrySummary?
    var currentYear: Int
    var recordedDaysThisYear: Int
    var totalDaysThisYear: Int

    static var empty: WidgetSnapshot {
        let calendar = Calendar.current
        let now = Date()
        return WidgetSnapshot(
            generatedAt: now,
            today: nil,
            latest: nil,
            currentYear: calendar.component(.year, from: now),
            recordedDaysThisYear: 0,
            totalDaysThisYear: Self.daysInYear(containing: now, calendar: calendar)
        )
    }

    static func daysInYear(containing date: Date, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return 365 }
        return calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 365
    }
}

struct WidgetEntrySummary: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var moodTitle: String
    var weatherSummary: String?
    var temperature: Double?
    var note: String
    var imageFilename: String?

    var hasImage: Bool {
        imageFilename != nil
    }

    var weatherText: String {
        guard let weatherSummary else { return "未记录天气" }
        if let temperature {
            return "\(weatherSummary) \(temperature.roundedText)°C"
        }
        return weatherSummary
    }
}

extension Double {
    fileprivate var roundedText: String {
        String(format: "%.0f", self)
    }
}
