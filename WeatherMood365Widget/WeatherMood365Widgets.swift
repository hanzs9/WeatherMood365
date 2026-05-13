import SwiftUI
import UIKit
import WidgetKit

struct WeatherMoodWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WeatherMoodWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherMoodWidgetEntry {
        WeatherMoodWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherMoodWidgetEntry) -> Void) {
        completion(WeatherMoodWidgetEntry(date: Date(), snapshot: Self.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherMoodWidgetEntry>) -> Void) {
        let now = Date()
        let entry = WeatherMoodWidgetEntry(date: now, snapshot: Self.loadSnapshot())
        let nextRefresh = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static func loadSnapshot() -> WidgetSnapshot {
        guard let snapshotURL = WidgetSharedStore.snapshotURL,
              let data = try? Data(contentsOf: snapshotURL) else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}

@main
struct WeatherMood365WidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayStatusWidget()
        RecentRecordWidget()
        YearProgressWidget()
    }
}

struct TodayStatusWidget: Widget {
    let kind = "TodayStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherMoodWidgetProvider()) { entry in
            TodayStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("今日打卡")
        .description("查看今天是否已经记录天气、心情和照片。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentRecordWidget: Widget {
    let kind = "RecentRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherMoodWidgetProvider()) { entry in
            RecentRecordWidgetView(entry: entry)
        }
        .configurationDisplayName("最近记录")
        .description("快速回看最近一条天气心情记录。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct YearProgressWidget: Widget {
    let kind = "YearProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherMoodWidgetProvider()) { entry in
            YearProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("年度进度")
        .description("查看今年已经记录了多少天。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherMoodWidgetEntry

    private var today: WidgetEntrySummary? {
        entry.snapshot.today
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(WidgetTheme.backgroundGradient, for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: today == nil ? "camera.fill" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(today == nil ? WidgetTheme.accent : .green)
                    .frame(width: 28, height: 28)
                Spacer()
                Text(Date(), formatter: WidgetFormatters.monthDay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 4)

            Text(today == nil ? "今天还没记录" : "今天已记录")
                .font(.headline.weight(.bold))
                .lineLimit(2)

            if let today {
                Text("\(today.weatherText) · \(today.moodTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            } else {
                Text("拍一张照片，留下今天。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(WidgetTheme.smallPadding)
    }

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            WidgetPhoto(filename: today?.imageFilename, cornerRadius: 16)
                .frame(width: 116)

            VStack(alignment: .leading, spacing: 8) {
                Text(today == nil ? "今天还没记录" : "今天已记录")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(Date(), formatter: WidgetFormatters.fullDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let today {
                    Text(today.weatherText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(today.moodTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if !today.note.isEmpty {
                        Text(today.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                } else {
                    Text("记录天气、心情和一句话。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WidgetTheme.mediumPadding)
    }
}

private struct RecentRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherMoodWidgetEntry

    private var latest: WidgetEntrySummary? {
        entry.snapshot.latest
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(Color(.systemBackground), for: .widget)
    }

    private var smallLayout: some View {
        ZStack(alignment: .bottomLeading) {
            WidgetPhoto(filename: latest?.imageFilename, cornerRadius: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(latest.map { WidgetFormatters.monthDay.string(from: $0.date) } ?? "暂无记录")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let latest {
                    Text("\(latest.weatherText) · \(latest.moodTitle)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(WidgetTheme.smallPadding)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            WidgetPhoto(filename: latest?.imageFilename, cornerRadius: 16)
                .frame(width: 128)

            VStack(alignment: .leading, spacing: 8) {
                Text("最近记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let latest {
                    Text(latest.date, formatter: WidgetFormatters.fullDate)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .monospacedDigit()
                        .minimumScaleFactor(0.76)
                    Text(latest.weatherText)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(latest.moodTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if !latest.note.isEmpty {
                        Text(latest.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                } else {
                    Text("还没有记录")
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text("从今天开始留下第一张照片。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WidgetTheme.mediumPadding)
    }
}

private struct YearProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherMoodWidgetEntry

    private var progress: Double {
        guard entry.snapshot.totalDaysThisYear > 0 else { return 0 }
        return Double(entry.snapshot.recordedDaysThisYear) / Double(entry.snapshot.totalDaysThisYear)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(WidgetTheme.backgroundGradient, for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(verbatim: String(entry.snapshot.currentYear))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.16), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WidgetTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.snapshot.recordedDaysThisYear)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("\(entry.snapshot.totalDaysThisYear)天")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 72, height: 72)

            Text("已记录天数")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(WidgetTheme.smallPadding)
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.16), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WidgetTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "\(String(entry.snapshot.currentYear)) 年度进度")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("已记录 \(entry.snapshot.recordedDaysThisYear) / \(entry.snapshot.totalDaysThisYear) 天")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                ProgressView(value: progress)
                    .tint(WidgetTheme.accent)

                if let latest = entry.snapshot.latest {
                    Text("最近：\(WidgetFormatters.monthDay.string(from: latest.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } else {
                    Text("还没有记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(WidgetTheme.mediumPadding)
    }
}

private struct WidgetPhoto: View {
    var filename: String?
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let filename,
               let url = WidgetSharedStore.imageURL(named: filename),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.97, blue: 1.0),
                            Color(red: 1.0, green: 0.95, blue: 0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "camera.aperture")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(WidgetTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private enum WidgetTheme {
    static let accent = Color(red: 0.17, green: 0.43, blue: 0.61)
    static let smallPadding: CGFloat = 14
    static let mediumPadding: CGFloat = 14
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.99, blue: 1.0),
            Color(red: 0.93, green: 0.96, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private enum WidgetFormatters {
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}
