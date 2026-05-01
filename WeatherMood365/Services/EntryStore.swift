import Foundation
import SwiftUI

@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [DailyEntry] = []
    @Published private(set) var version = 0

    private(set) var sortedEntries: [DailyEntry] = []

    private let fileManager = FileManager.default
    private var entriesByDay: [Date: DailyEntry] = [:]
    private let calendar = Calendar.current

    init() {
        load()
    }

    func entry(for date: Date) -> DailyEntry? {
        entriesByDay[dayKey(for: date)]
    }

    func upsert(_ entry: DailyEntry, imageData: Data?) {
        var savedEntry = entry
        let existingByID = entries.first { $0.id == entry.id }
        let existingForDay = entries.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }

        if let imageData {
            savedEntry.photoFilename = savePhoto(imageData, for: entry.date)
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
        applyEntries(updatedEntries)
        save()
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
        save()
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
            print("Failed to load entries: \(error)")
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to save entries: \(error)")
        }
    }

    private func savePhoto(_ data: Data, for date: Date) -> String? {
        do {
            if !fileManager.fileExists(atPath: photosDirectory.path) {
                try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            }

            let filename = "\(Self.filenameFormatter.string(from: date)).jpg"
            let url = photosDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            PhotoImageCache.shared.removeImages(for: url)
            return filename
        } catch {
            print("Failed to save photo: \(error)")
            return nil
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
