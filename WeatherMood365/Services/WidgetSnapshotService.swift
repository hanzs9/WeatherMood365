import Foundation
import ImageIO
import OSLog
import UIKit
import WidgetKit

@MainActor
final class WidgetSnapshotService {
    static let shared = WidgetSnapshotService()

    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.han.WeatherMood365", category: "widget")

    private init() {}

    func sync(entries: [DailyEntry], sortedEntries: [DailyEntry], imageURLProvider: (DailyEntry) -> URL?) {
        guard let containerURL = WidgetSharedStore.containerURL,
              let snapshotURL = WidgetSharedStore.snapshotURL else {
            logger.error("Widget snapshot skipped because App Group container is unavailable")
            return
        }

        let today = Date()
        let todayEntry = entries.first { calendar.isDate($0.date, inSameDayAs: today) }
        let latestEntry = sortedEntries.first
        let year = calendar.component(.year, from: today)
        let recordedDaysThisYear = entries.filter { calendar.component(.year, from: $0.date) == year }.count

        let todayImageURL = todayEntry.flatMap { imageURLProvider($0) }
        let latestImageURL = latestEntry.flatMap { imageURLProvider($0) }

        let todaySummary = todayEntry.map { WidgetSnapshotService.summary(for: $0, imageFilename: nil) }
        let latestSummary = latestEntry.map { WidgetSnapshotService.summary(for: $0, imageFilename: nil) }

        Task.detached(priority: .background) {
            let fileManager = FileManager.default

            do {
                try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)

                let todayImageFilename = WidgetSnapshotService.writeWidgetImage(from: todayImageURL, preferredFilename: WidgetSharedStore.todayImageFilename, containerURL: containerURL)
                let latestImageFilename = WidgetSnapshotService.writeWidgetImage(from: latestImageURL, preferredFilename: WidgetSharedStore.latestImageFilename, containerURL: containerURL)

                let todaySummaryWithImage = todaySummary.map { WidgetEntrySummary(id: $0.id, date: $0.date, moodTitle: $0.moodTitle, weatherSummary: $0.weatherSummary, temperature: $0.temperature, note: $0.note, imageFilename: todayImageFilename) }
                let latestSummaryWithImage = latestSummary.map { WidgetEntrySummary(id: $0.id, date: $0.date, moodTitle: $0.moodTitle, weatherSummary: $0.weatherSummary, temperature: $0.temperature, note: $0.note, imageFilename: latestImageFilename) }

                let snapshot = WidgetSnapshot(
                    generatedAt: today,
                    today: todaySummaryWithImage,
                    latest: latestSummaryWithImage,
                    currentYear: year,
                    recordedDaysThisYear: recordedDaysThisYear,
                    totalDaysThisYear: WidgetSnapshot.daysInYear(containing: today, calendar: Calendar.current)
                )

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: snapshotURL, options: .atomic)
                self.logger.log("Widget snapshot updated for \(entries.count) entries")
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                self.logger.error("Failed to sync widget snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func summary(for entry: DailyEntry, imageFilename: String?) -> WidgetEntrySummary {
        WidgetEntrySummary(
            id: entry.id,
            date: entry.date,
            moodTitle: entry.mood.title,
            weatherSummary: entry.weather?.summary,
            temperature: entry.weather?.temperature,
            note: entry.note,
            imageFilename: imageFilename
        )
    }

    private nonisolated static func writeWidgetImage(
        from sourceURL: URL?,
        preferredFilename: String,
        containerURL: URL
    ) -> String? {
        let destinationURL = containerURL.appendingPathComponent(preferredFilename)
        let fileManager = FileManager.default

        guard let sourceURL,
              fileManager.fileExists(atPath: sourceURL.path),
              let imageData = downsampledJPEGData(at: sourceURL, maxPixelSize: 900) else {
            try? fileManager.removeItem(at: destinationURL)
            return nil
        }

        do {
            try imageData.write(to: destinationURL, options: .atomic)
            return preferredFilename
        } catch {
            Logger(subsystem: "com.han.WeatherMood365", category: "widget").error(
                "Failed to write widget image: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private nonisolated static func downsampledJPEGData(at url: URL, maxPixelSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
    }
}
