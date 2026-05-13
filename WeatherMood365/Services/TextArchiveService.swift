import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TextArchiveError: LocalizedError {
    case invalidFormat
    case unsupportedVersion
    case unreadableDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "不是 WeatherMood365 文本归档文件。"
        case .unsupportedVersion:
            "暂不支持这个归档版本。"
        case .unreadableDate(let date):
            "无法读取日期：\(date)"
        }
    }
}

struct TextArchive: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let records: [TextArchiveRecord]
}

struct TextArchiveRecord: Codable {
    let date: String
    let mood: String
    let moodTitle: String
    let note: String
    let weatherSummary: String?
    let temperature: Double?
    let weatherCode: Int?
    let weatherFetchedAt: String?
}

struct TextArchiveImportResult {
    var added: Int
    var updated: Int
    var skipped: Int
}

struct ExportedTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [markdownContentType, .plainText, .json] }
    static var writableContentTypes: [UTType] { [markdownContentType, .plainText, .json] }

    private static var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum TextExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .json:
            .json
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }
}

@MainActor
enum TextArchiveService {
    static let format = "WeatherMood365TextArchive"
    static let version = 1

    static func exportText(entries: [DailyEntry], format exportFormat: TextExportFormat, scopeTitle: String) throws -> String {
        switch exportFormat {
        case .markdown:
            return exportMarkdown(entries: entries, scopeTitle: scopeTitle)
        case .json:
            let archive = makeArchive(entries: entries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(archive)
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func decodeArchive(from data: Data) throws -> TextArchive {
        let archive = try JSONDecoder().decode(TextArchive.self, from: data)
        guard archive.format == format else {
            throw TextArchiveError.invalidFormat
        }
        guard archive.version == version else {
            throw TextArchiveError.unsupportedVersion
        }
        return archive
    }

    static func date(from archiveDate: String) -> Date? {
        archiveDateFormatter.date(from: archiveDate)
    }

    static func archiveDateString(for date: Date) -> String {
        archiveDateFormatter.string(from: date)
    }

    private static func makeArchive(entries: [DailyEntry]) -> TextArchive {
        TextArchive(
            format: format,
            version: version,
            exportedAt: isoFormatter.string(from: Date()),
            records: entries.map { entry in
                TextArchiveRecord(
                    date: archiveDateString(for: entry.date),
                    mood: entry.mood.rawValue,
                    moodTitle: entry.mood.title,
                    note: entry.note,
                    weatherSummary: entry.weather?.summary,
                    temperature: entry.weather?.temperature,
                    weatherCode: entry.weather?.weatherCode,
                    weatherFetchedAt: entry.weather.map { isoFormatter.string(from: $0.fetchedAt) }
                )
            }
        )
    }

    private static func exportMarkdown(entries: [DailyEntry], scopeTitle: String) -> String {
        var lines: [String] = [
            "# WeatherMood365 日记",
            "",
            "- 范围：\(scopeTitle)",
            "- 记录数：\(entries.count)",
            "- 导出时间：\(readableDateTimeFormatter.string(from: Date()))",
            ""
        ]

        for entry in entries {
            lines.append("## \(readableDateFormatter.string(from: entry.date))")
            lines.append("")
            lines.append("- 天气：\(weatherText(for: entry))")
            lines.append("- 心情：\(entry.mood.title)")
            lines.append("- 一句话：\(noteText(for: entry.note))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func weatherText(for entry: DailyEntry) -> String {
        guard let weather = entry.weather else { return "未记录" }
        return "\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C"
    }

    private static func noteText(for note: String) -> String {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "未填写" }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let readableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private static let readableDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
