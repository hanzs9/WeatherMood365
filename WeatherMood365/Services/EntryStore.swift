import Foundation
import OSLog
import SwiftUI

struct EntrySaveResult {
    var warningMessage: String?
    var savedToSystemLibrary = false
    var addedToDedicatedAlbum = false
}

enum EntryStoreError: LocalizedError {
    case photoSaveFailed
    case entriesSaveFailed

    var errorDescription: String? {
        switch self {
        case .photoSaveFailed:
            "照片保存失败，请稍后重试。"
        case .entriesSaveFailed:
            "记录保存失败，请稍后重试。"
        }
    }
}

@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [DailyEntry] = []
    @Published private(set) var version = 0

    private(set) var sortedEntries: [DailyEntry] = []

    private let fileManager = FileManager.default
    private var entriesByDay: [Date: DailyEntry] = [:]
    private let calendar = Calendar.current
    private let saveQueue = DispatchQueue(label: "com.han.WeatherMood365.save", qos: .background)
    private let logger = Logger(subsystem: "com.han.WeatherMood365", category: "entry-store")

    init() {
        load()
        syncWidgetSnapshot()
    }

    func entry(for date: Date) -> DailyEntry? {
        entriesByDay[dayKey(for: date)]
    }

    func upsert(_ entry: DailyEntry, imageData: Data?, photoSource: PickedPhoto.Source? = nil) async throws -> EntrySaveResult {
        logger.log("Starting entry save for date: \(entry.date.formatted(.iso8601.year().month().day()), privacy: .public)")
        var savedEntry = entry
        savedEntry.updatedAt = Date()
        let existingByID = entries.first { $0.id == entry.id }
        let existingForDay = entries.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }

        if let imageData {
            savedEntry.photoFilename = try await savePhoto(imageData, for: entry.date)
        } else if savedEntry.photoFilename == nil {
            savedEntry.photoFilename = existingByID?.photoFilename ?? existingForDay?.photoFilename
        }

        if let existingByID {
            savedEntry.id = existingByID.id
        } else if let existingForDay {
            savedEntry.id = existingForDay.id
        }

        var updatedEntries = entries
        updatedEntries.removeAll {
            $0.id == savedEntry.id || calendar.isDate($0.date, inSameDayAs: savedEntry.date)
        }
        updatedEntries.append(savedEntry)
        try await save(entries: updatedEntries)
        applyEntries(updatedEntries)
        syncDailyReminder()
        syncWidgetSnapshot()

        var warningMessage: String?
        var savedToSystemLibrary = false
        var addedToDedicatedAlbum = false
        if let imageData,
           shouldSyncPhotoCopyToLibrary(for: photoSource) {
            do {
                let syncResult = try await syncPhotoToWeatherAlbum(imageData, for: savedEntry)
                savedToSystemLibrary = syncResult.savedToLibrary
                addedToDedicatedAlbum = syncResult.addedToWeatherMoodAlbum
                warningMessage = syncResult.warningMessage
            } catch {
                warningMessage = "记录已保存，但同步到系统相册失败：\(error.localizedDescription)"
            }
        }

        logger.log("Entry save completed for date: \(savedEntry.date.formatted(.iso8601.year().month().day()), privacy: .public)")
        return EntrySaveResult(
            warningMessage: warningMessage,
            savedToSystemLibrary: savedToSystemLibrary,
            addedToDedicatedAlbum: addedToDedicatedAlbum
        )
    }

    func imageURL(for entry: DailyEntry) -> URL? {
        guard let photoFilename = entry.photoFilename else { return nil }
        return photosDirectory.appendingPathComponent(photoFilename)
    }

    func delete(_ entry: DailyEntry) {
        let entriesToDelete = entries.filter {
            $0.id == entry.id || calendar.isDate($0.date, inSameDayAs: entry.date)
        }
        let photoFilenames = Set(entriesToDelete.compactMap(\.photoFilename))

        for photoFilename in photoFilenames {
            let url = photosDirectory.appendingPathComponent(photoFilename)
            try? fileManager.removeItem(at: url)
            PhotoImageCache.shared.removeImages(for: url)
        }

        var updatedEntries = entries
        updatedEntries.removeAll {
            $0.id == entry.id || calendar.isDate($0.date, inSameDayAs: entry.date)
        }
        applyEntries(updatedEntries)
        Task {
            do {
                try await save(entries: updatedEntries)
            } catch {
                logger.error("Failed to persist deleted entries: \(error.localizedDescription, privacy: .public)")
            }
        }
        syncDailyReminder()
        syncWidgetSnapshot()
    }

    func importTextArchive(_ archive: TextArchive) -> TextArchiveImportResult {
        var updatedEntries = entries
        var result = TextArchiveImportResult(added: 0, updated: 0, skipped: 0)

        for record in archive.records {
            guard let date = TextArchiveService.date(from: record.date),
                  let mood = Mood(rawValue: record.mood) else {
                result.skipped += 1
                continue
            }

            let weather = weatherSnapshot(from: record)
            if let index = updatedEntries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                updatedEntries[index].date = date
                updatedEntries[index].mood = mood
                updatedEntries[index].note = record.note
                updatedEntries[index].weather = weather
                updatedEntries[index].updatedAt = Date()
                result.updated += 1
            } else {
                updatedEntries.append(DailyEntry(
                    date: date,
                    mood: mood,
                    note: record.note,
                    weather: weather
                ))
                result.added += 1
            }
        }

        if result.added > 0 || result.updated > 0 {
            applyEntries(updatedEntries)
            Task {
                do {
                    try await save(entries: updatedEntries)
                } catch {
                    logger.error("Failed to persist imported entries: \(error.localizedDescription, privacy: .public)")
                }
            }
            syncDailyReminder()
            syncWidgetSnapshot()
        }

        return result
    }

    private var storeURL: URL {
        documentsDirectory.appendingPathComponent("entries.json")
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var photosDirectory: URL {
        documentsDirectory.appendingPathComponent("Photos", isDirectory: true)
    }

    private func load() {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        do {
            let data = try Data(contentsOf: storeURL)
            applyEntries(try JSONDecoder().decode([DailyEntry].self, from: data), advanceVersion: false)
        } catch {
            logger.error("Failed to load entries: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyEntries(_ newEntries: [DailyEntry], advanceVersion: Bool = true) {
        sortedEntries = newEntries.sorted { $0.date > $1.date }
        entriesByDay = newEntries.reduce(into: [:]) { result, entry in
            result[dayKey(for: entry.date)] = entry
        }
        entries = newEntries
        if advanceVersion {
            version += 1
        }
    }

    private func dayKey(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func save(entries: [DailyEntry]) async throws {
        let url = storeURL
        try await withCheckedThrowingContinuation { continuation in
            saveQueue.async {
                do {
                    let data = try JSONEncoder().encode(entries)
                    try data.write(to: url, options: .atomic)
                    self.logger.log("Persisted \(entries.count) entries to disk")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to save entries: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: EntryStoreError.entriesSaveFailed)
                }
            }
        }
    }

    private func syncPhotoToWeatherAlbum(_ imageData: Data, for entry: DailyEntry) async throws -> PhotoLibrarySyncResult {
        logger.log("Syncing saved photo to system library for date: \(entry.date.formatted(.iso8601.year().month().day()), privacy: .public)")
        return try await WeatherPhotoLibraryService.shared.savePhoto(
            data: imageData,
            date: entry.date,
            location: entry.photoLocation
        )
    }

    private func savePhoto(_ data: Data, for date: Date) async throws -> String {
        let photosDirectory = photosDirectory
        let filename = "\(Self.filenameFormatter.string(from: date)).jpg"
        let url = photosDirectory.appendingPathComponent(filename)

        return try await withCheckedThrowingContinuation { continuation in
            saveQueue.async {
                do {
                    let fileManager = FileManager.default
                    if !fileManager.fileExists(atPath: photosDirectory.path) {
                        try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
                    }

                    try data.write(to: url, options: .atomic)
                    PhotoImageCache.shared.removeImages(for: url)
                    self.logger.log("Saved photo file to sandbox: \(filename, privacy: .public)")
                    continuation.resume(returning: filename)
                } catch {
                    self.logger.error("Failed to save photo file: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: EntryStoreError.photoSaveFailed)
                }
            }
        }
    }

    private func weatherSnapshot(from record: TextArchiveRecord) -> WeatherSnapshot? {
        guard let weatherCode = record.weatherCode else { return nil }

        let fetchedAt = record.weatherFetchedAt
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return WeatherSnapshot(
            temperature: record.temperature ?? 0,
            windSpeed: 0,
            weatherCode: weatherCode,
            fetchedAt: fetchedAt,
            visibility: nil,
            aqi: nil,
            aerosolOpticalDepth: nil
        )
    }

    private func syncDailyReminder() {
        Task {
            await ReminderService.shared.syncReminder(with: self)
        }
    }

    private func syncWidgetSnapshot() {
        WidgetSnapshotService.shared.sync(entries: entries, sortedEntries: sortedEntries) { [weak self] entry in
            self?.imageURL(for: entry)
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func shouldSyncPhotoCopyToLibrary(for source: PickedPhoto.Source?) -> Bool {
        guard UserDefaults.standard.bool(forKey: WeatherPhotoLibraryService.syncToLibraryEnabledKey) else {
            return false
        }

        return source == .camera
    }
}
