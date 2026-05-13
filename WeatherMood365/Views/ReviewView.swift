import SwiftUI
import UIKit

struct ReviewView: View {
    @EnvironmentObject private var store: EntryStore

    @State private var mode: ReviewMode = .month
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var exportMessage: String?
    @State private var previewState: ReviewPhotoPreview?
    @State private var cachedSummary: ReviewSummary?
    @State private var cachedVersion: Int = -1
    @State private var cachedMode: ReviewMode = .month
    @State private var cachedYear: Int = 0
    @State private var cachedMonth: Int = 0

    private var summary: ReviewSummary {
        if let cachedSummary,
           cachedVersion == store.version,
           cachedMode == mode,
           cachedYear == selectedYear,
           cachedMonth == selectedMonth {
            return cachedSummary
        }
        let newSummary = ReviewSummary(
            entries: store.sortedEntries,
            mode: mode,
            year: selectedYear,
            month: selectedMonth,
            imageURLProvider: store.imageURL(for:)
        )
        cachedSummary = newSummary
        cachedVersion = store.version
        cachedMode = mode
        cachedYear = selectedYear
        cachedMonth = selectedMonth
        return newSummary
    }

    private var years: [Int] {
        let years = Set(store.sortedEntries.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    private var availableMonths: [Int] {
        let months = Set(store.sortedEntries.compactMap { entry -> Int? in
            guard Calendar.current.component(.year, from: entry.date) == selectedYear else { return nil }
            return Calendar.current.component(.month, from: entry.date)
        })
        return months.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                mapEntrySection

                if store.sortedEntries.isEmpty {
                    ContentUnavailableView(
                        "还没有足够的记录生成回顾",
                        systemImage: "chart.pie",
                        description: Text("继续每天记录照片、天气和心情，之后这里会生成年度和月度回顾。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                } else {
                    controlsSection

                    if summary.entries.isEmpty {
                        ContentUnavailableView(
                            "这个时间段还没有记录",
                            systemImage: "calendar",
                            description: Text("切换年份或月份查看已有记录。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .listRowBackground(Color.clear)
                    } else {
                        summarySection
                        insightSection
                        motivationSection
                        moodSection
                        weatherSection
                        photosSection
                        notesSection
                    }
                }
            }
            .navigationTitle("回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPoster()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(summary.entries.isEmpty)
                    .accessibilityLabel("导出回顾海报")
                }
            }
            .onAppear {
                normalizeSelection()
            }
            .onChange(of: store.version) { _, _ in
                normalizeSelection()
            }
            .onChange(of: selectedYear) { _, _ in
                normalizeMonth()
            }
            .alert("回顾海报", isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(exportMessage ?? "")
            }
            .fullScreenCover(item: $previewState) { preview in
                ImagePreviewView(image: preview.image)
            }
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("回顾类型", selection: $mode) {
                ForEach(ReviewMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("年份", selection: $selectedYear) {
                ForEach(years, id: \.self) { year in
                    Text(verbatim: "\(String(year)) 年")
                        .tag(year)
                }
            }

            if mode == .month {
                Picker("月份", selection: $selectedMonth) {
                    ForEach(availableMonths, id: \.self) { month in
                        Text("\(month) 月")
                            .tag(month)
                    }
                }
            }
        }
    }

    private var mapEntrySection: some View {
        Section {
            NavigationLink {
                LocationMapView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "map.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.appAccent)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("照片地图")
                            .font(.headline)
                        Text("按位置回看有坐标的记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.standard))
            }
            .buttonStyle(.pressableCard(cornerRadius: AppRadius.standard, pressedScale: 0.98, overlayColor: .black.opacity(0.05)))
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary.title)
                    .font(.title2.weight(.bold))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ReviewMetricCard(title: "记录天数", value: "\(summary.recordedDays)", subtitle: "\(summary.totalDays) 天中的记录")
                    ReviewMetricCard(title: "记录率", value: "\(summary.recordRate)%", subtitle: "这个周期的完成度")
                    ReviewMetricCard(title: "最常心情", value: summary.topMoodTitle, subtitle: "出现最多")
                    ReviewMetricCard(title: "最常天气", value: summary.topWeatherTitle, subtitle: "出现最多")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var insightSection: some View {
        Section("智能总结") {
            VStack(alignment: .leading, spacing: 16) {
                Text(summary.insight.summaryText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !summary.insight.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("常出现的词")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(summary.insight.keywords, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.appAccent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color(red: 0.12, green: 0.34, blue: 0.50))
                            }
                        }
                    }
                }

                if summary.insight.trendPoints.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("心情趋势")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        MoodTrendChart(points: summary.insight.trendPoints)
                            .frame(height: 126)

                        Text(summary.insight.trendText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var motivationSection: some View {
        Section("打卡动力") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ReviewMetricCard(title: "当前连续", value: "\(summary.currentStreak)", subtitle: "天")
                ReviewMetricCard(title: "最长连续", value: "\(summary.longestStreak)", subtitle: "天")
                ReviewMetricCard(title: summary.remainingTitle, value: "\(summary.remainingDaysForGoal)", subtitle: "天")
            }

            Text(summary.motivationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var moodSection: some View {
        Section("心情分布") {
            ForEach(Mood.allCases) { mood in
                ReviewBarRow(
                    title: mood.title,
                    count: summary.moodCounts[mood, default: 0],
                    total: max(summary.entries.count, 1),
                    leading: AnyView(MoodIconView(mood: mood, size: 20))
                )
            }
        }
    }

    @ViewBuilder
    private var weatherSection: some View {
        if !summary.weatherCounts.isEmpty {
            Section("天气分布") {
                ForEach(summary.weatherRows, id: \.title) { row in
                    ReviewBarRow(
                        title: row.title,
                        count: row.count,
                        total: max(summary.entriesWithWeatherCount, 1),
                        leading: AnyView(Image(systemName: row.symbol).foregroundStyle(.blue).frame(width: 22))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        if !summary.photoEntries.isEmpty {
            Section("精选照片") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(summary.featuredPhotoEntries) { entry in
                        Button {
                            showPreview(for: entry)
                        } label: {
                            CachedPhotoView(
                                url: store.imageURL(for: entry),
                                targetSize: CGSize(width: 260, height: 260),
                                contentMode: .fill,
                                refreshToken: store.version
                            ) {
                                Color.secondary.opacity(0.12)
                            }
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.pressableCard(
                            cornerRadius: 8,
                            pressedScale: 0.98,
                            overlayColor: .black.opacity(0.06),
                            shadowColor: .black.opacity(0.1),
                            shadowRadius: 8,
                            shadowY: 3
                        ))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func showPreview(for entry: DailyEntry) {
        guard let url = store.imageURL(for: entry) else { return }

        Task {
            let targetSize = CGSize(width: 1200, height: 1200)
            let image = await PhotoImageCache.shared.image(for: url, targetSize: targetSize, scale: UIScreen.main.scale)

            guard store.imageURL(for: entry) == url else { return }
            if let image {
                previewState = ReviewPhotoPreview(image: image)
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !summary.noteEntries.isEmpty {
            Section("一句话摘录") {
                ForEach(summary.noteEntries.prefix(5)) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.date, format: .dateTime.year().month().day())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.note)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func normalizeSelection() {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())

        if store.sortedEntries.contains(where: {
            let components = calendar.dateComponents([.year, .month], from: $0.date)
            return components.year == currentYear && components.month == currentMonth
        }) {
            selectedYear = currentYear
            selectedMonth = currentMonth
        } else if let latest = store.sortedEntries.first {
            selectedYear = calendar.component(.year, from: latest.date)
            selectedMonth = calendar.component(.month, from: latest.date)
        } else if let firstYear = years.first, !years.contains(selectedYear) {
            selectedYear = firstYear
        }
        normalizeMonth()
    }

    private func normalizeMonth() {
        guard mode == .month else { return }
        if let firstMonth = availableMonths.first, !availableMonths.contains(selectedMonth) {
            selectedMonth = firstMonth
        }
    }

    private func exportPoster() {
        let image = ReviewPosterRenderer.render(summary: summary)
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        exportMessage = "已导出到相册。"
    }
}

private struct ReviewPhotoPreview: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ReviewMode: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year: "年度"
        case .month: "月度"
        }
    }
}

private struct ReviewMetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.standard))
    }
}

private struct ReviewBarRow: View {
    let title: String
    let count: Int
    let total: Int
    let leading: AnyView

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            leading

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(Color.appAccent)
                            .frame(width: max(proxy.size.width * progress, count > 0 ? 8 : 0))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MoodTrendChart: View {
    let points: [MoodTrendPoint]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let chartRect = CGRect(
                    x: 12,
                    y: 10,
                    width: max(proxy.size.width - 24, 1),
                    height: max(proxy.size.height - 32, 1)
                )

                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let y = chartRect.minY + chartRect.height * CGFloat(index) / 2
                        Path { path in
                            path.move(to: CGPoint(x: chartRect.minX, y: y))
                            path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                        }
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                    }

                    trendPath(in: chartRect)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.appAccent,
                                    Color(red: 0.96, green: 0.66, blue: 0.23)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.appAccent, lineWidth: 2))
                            .position(position(for: point.score, index: index, in: chartRect))
                    }
                }
            }

            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                Text(points.last?.label ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trendPath(in rect: CGRect) -> Path {
        Path { path in
            guard !points.isEmpty else { return }
            for (index, point) in points.enumerated() {
                let position = position(for: point.score, index: index, in: rect)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
    }

    private func position(for score: Double, index: Int, in rect: CGRect) -> CGPoint {
        let x: CGFloat
        if points.count <= 1 {
            x = rect.midX
        } else {
            x = rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1)
        }
        let clamped = min(max(score, 1), 5)
        let y = rect.maxY - rect.height * CGFloat((clamped - 1) / 4)
        return CGPoint(x: x, y: y)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ReviewSummary {
    let entries: [DailyEntry]
    let mode: ReviewMode
    let year: Int
    let month: Int
    let imageURLProvider: (DailyEntry) -> URL?

    private let calendar = Calendar.current

    init(entries allEntries: [DailyEntry], mode: ReviewMode, year: Int, month: Int, imageURLProvider: @escaping (DailyEntry) -> URL?) {
        self.mode = mode
        self.year = year
        self.month = month
        self.imageURLProvider = imageURLProvider
        let calendar = Calendar.current
        self.entries = allEntries.filter { entry in
            let components = calendar.dateComponents([.year, .month], from: entry.date)
            switch mode {
            case .year:
                return components.year == year
            case .month:
                return components.year == year && components.month == month
            }
        }
    }

    var title: String {
        switch mode {
        case .year: "\(String(year)) 年回顾"
        case .month: "\(String(year)) 年 \(month) 月回顾"
        }
    }

    var recordedDays: Int {
        entries.count
    }

    var totalDays: Int {
        switch mode {
        case .year:
            guard let date = calendar.date(from: DateComponents(year: year)),
                  let interval = calendar.dateInterval(of: .year, for: date) else { return 365 }
            return calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 365
        case .month:
            guard let date = calendar.date(from: DateComponents(year: year, month: month)),
                  let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
            return range.count
        }
    }

    var recordRate: Int {
        guard totalDays > 0 else { return 0 }
        return Int((Double(recordedDays) / Double(totalDays) * 100).rounded())
    }

    var currentStreak: Int {
        let dates = recordedDateSet
        guard !dates.isEmpty else { return 0 }

        let endDate = min(calendar.startOfDay(for: Date()), periodEndDate)
        guard endDate >= periodStartDate else { return 0 }

        var cursor = endDate
        var streak = 0
        while cursor >= periodStartDate {
            if dates.contains(cursor) {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            } else if streak == 0 {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            } else {
                break
            }
        }
        return streak
    }

    var longestStreak: Int {
        let dates = recordedDateSet.sorted()
        guard !dates.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in dates.indices.dropFirst() {
            let previous = dates[dates.index(before: index)]
            let date = dates[index]
            if calendar.dateComponents([.day], from: previous, to: date).day == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }

    var remainingDaysForGoal: Int {
        max(totalDays - recordedDays, 0)
    }

    var remainingTitle: String {
        switch mode {
        case .year: "距全年"
        case .month: "距全勤"
        }
    }

    var motivationText: String {
        if recordedDays == 0 {
            return "这个周期还没开始记录，拍下第一张就有了起点。"
        }

        switch mode {
        case .year:
            return "今年最长连续 \(longestStreak) 天，距离全年完整记录还差 \(remainingDaysForGoal) 天。"
        case .month:
            return "本月最长连续 \(longestStreak) 天，距离全勤还差 \(remainingDaysForGoal) 天。"
        }
    }

    var moodCounts: [Mood: Int] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.mood, default: 0] += 1
        }
    }

    var topMoodTitle: String {
        moodCounts.max { $0.value < $1.value }?.key.title ?? "未记录"
    }

    var weatherCounts: [String: Int] {
        entries.reduce(into: [:]) { result, entry in
            guard let weather = entry.weather else { return }
            result[weather.summary, default: 0] += 1
        }
    }

    var weatherRows: [(title: String, count: Int, symbol: String)] {
        weatherCounts
            .map { title, count in
                (title: title, count: count, symbol: weatherSymbol(for: title))
            }
            .sorted {
                if $0.count == $1.count { return $0.title < $1.title }
                return $0.count > $1.count
            }
    }

    var topWeatherTitle: String {
        weatherRows.first?.title ?? "未记录"
    }

    var entriesWithWeatherCount: Int {
        entries.filter { $0.weather != nil }.count
    }

    var photoEntries: [DailyEntry] {
        entries.filter { imageURLProvider($0) != nil }.sorted { $0.date < $1.date }
    }

    var featuredPhotoEntries: [DailyEntry] {
        evenlyPicked(from: photoEntries, limit: 6)
    }

    var noteEntries: [DailyEntry] {
        entries
            .filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.date > $1.date }
    }

    var insight: ReviewInsight {
        ReviewInsight(summary: self)
    }

    private var recordedDateSet: Set<Date> {
        Set(entries.map { calendar.startOfDay(for: $0.date) })
    }

    private var periodStartDate: Date {
        switch mode {
        case .year:
            return calendar.date(from: DateComponents(year: year)) ?? calendar.startOfDay(for: Date())
        case .month:
            return calendar.date(from: DateComponents(year: year, month: month)) ?? calendar.startOfDay(for: Date())
        }
    }

    private var periodEndDate: Date {
        guard let end = calendar.date(byAdding: .day, value: totalDays - 1, to: periodStartDate) else {
            return periodStartDate
        }
        return end
    }

    private func evenlyPicked(from entries: [DailyEntry], limit: Int) -> [DailyEntry] {
        guard entries.count > limit, limit > 1 else { return Array(entries.prefix(limit)) }
        return (0..<limit).map { index in
            let sourceIndex = Int((Double(index) * Double(entries.count - 1) / Double(limit - 1)).rounded())
            return entries[sourceIndex]
        }
    }

    private func weatherSymbol(for title: String) -> String {
        switch title {
        case "晴朗": "sun.max.fill"
        case "多云": "cloud.sun.fill"
        case "有雾": "cloud.fog.fill"
        case "毛毛雨": "cloud.drizzle.fill"
        case "下雨", "阵雨": "cloud.rain.fill"
        case "下雪": "cloud.snow.fill"
        case "雷雨": "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

private struct ReviewInsight {
    let summaryText: String
    let keywords: [String]
    let trendPoints: [MoodTrendPoint]
    let trendText: String

    init(summary: ReviewSummary) {
        let entries = summary.entries.sorted { $0.date < $1.date }
        let keywords = Self.extractKeywords(from: entries)
        let trendPoints = Self.makeTrendPoints(from: entries, mode: summary.mode, calendar: Calendar.current)
        let trendText = Self.makeTrendText(points: trendPoints)

        self.keywords = keywords
        self.trendPoints = trendPoints
        self.trendText = trendText
        self.summaryText = Self.makeSummaryText(summary: summary, keywords: keywords, trendText: trendText)
    }

    private static func makeSummaryText(summary: ReviewSummary, keywords: [String], trendText: String) -> String {
        guard !summary.entries.isEmpty else {
            return "记录再多一些后，这里会生成更完整的回顾。"
        }

        let keywordText = keywords.prefix(3).joined(separator: "、")
        var parts: [String] = [
            "\(summary.title)里，你一共记录了 \(summary.recordedDays) 天，记录率约 \(summary.recordRate)%。",
            "最常见的心情是\(summary.topMoodTitle)，最常见的天气是\(summary.topWeatherTitle)。"
        ]

        if !trendText.isEmpty {
            parts.append(trendText)
        }

        if !keywordText.isEmpty {
            parts.append("一句话里经常出现「\(keywordText)」这些词。")
        }

        return parts.joined(separator: " ")
    }

    private static func makeTrendText(points: [MoodTrendPoint]) -> String {
        guard points.count > 1,
              let first = points.first?.score,
              let last = points.last?.score else {
            return ""
        }

        let delta = last - first
        if delta >= 0.55 {
            return "这段时间后半段的心情整体更明亮。"
        } else if delta <= -0.55 {
            return "这段时间后半段的心情略有下滑，可以多留意休息和节奏。"
        }

        let average = points.map(\.score).reduce(0, +) / Double(points.count)
        if average >= 4 {
            return "整体心情偏积极，惬意和开心的时刻比较多。"
        } else if average <= 2.2 {
            return "整体心情偏低，需要给自己多一点缓冲。"
        }

        return "这段时间的心情整体比较平稳。"
    }

    private static func makeTrendPoints(from entries: [DailyEntry], mode: ReviewMode, calendar: Calendar) -> [MoodTrendPoint] {
        guard entries.count > 1 else { return [] }

        switch mode {
        case .year:
            let grouped = Dictionary(grouping: entries) { entry in
                calendar.component(.month, from: entry.date)
            }
            return grouped.keys.sorted().compactMap { month in
                guard let monthEntries = grouped[month], !monthEntries.isEmpty else { return nil }
                return MoodTrendPoint(label: "\(month)月", score: averageMoodScore(monthEntries))
            }

        case .month:
            let grouped = Dictionary(grouping: entries) { entry in
                let day = calendar.component(.day, from: entry.date)
                return ((day - 1) / 7) + 1
            }
            return grouped.keys.sorted().compactMap { week in
                guard let weekEntries = grouped[week], !weekEntries.isEmpty else { return nil }
                return MoodTrendPoint(label: "第\(week)周", score: averageMoodScore(weekEntries))
            }
        }
    }

    private static func averageMoodScore(_ entries: [DailyEntry]) -> Double {
        let total = entries.map { $0.mood.reviewScore }.reduce(0, +)
        return Double(total) / Double(max(entries.count, 1))
    }

    private static func extractKeywords(from entries: [DailyEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            for token in tokenize(note) where !stopWords.contains(token) {
                counts[token, default: 0] += 1
            }
        }

        return counts
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(8)
            .map(\.key)
    }

    private static func tokenize(_ text: String) -> [String] {
        let lowercased = text.lowercased()
        let separators = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "\u{4e00}"..."\u{9fff}"))
            .inverted
        let roughTokens = lowercased
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        return roughTokens.flatMap { token -> [String] in
            if token.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil {
                return token.count >= 3 ? [token] : []
            }

            if token.count <= 4 {
                return token.count >= 2 ? [token] : []
            }

            return Array(chineseChunks(from: token))
        }
    }

    private static func chineseChunks(from token: String) -> [String] {
        var chunks: [String] = []
        let characters = Array(token)
        guard characters.count >= 2 else { return chunks }

        for size in [2, 3] {
            guard characters.count >= size else { continue }
            for start in 0...(characters.count - size) {
                let chunk = String(characters[start..<(start + size)])
                if !stopWords.contains(chunk) {
                    chunks.append(chunk)
                }
            }
        }

        return chunks
    }

    private static let stopWords: Set<String> = [
        "今天", "昨天", "明天", "感觉", "一下", "还是", "一个", "这个", "那个", "就是", "然后", "因为", "所以",
        "没有", "真的", "有点", "比较", "特别", "一起", "自己", "时候", "已经", "可以", "不是", "但是",
        "the", "and", "for", "with", "this", "that", "today"
    ]
}

private struct MoodTrendPoint: Equatable {
    let label: String
    let score: Double
}

private extension Mood {
    var reviewScore: Int {
        switch self {
        case .low: 1
        case .irritated: 2
        case .plain: 3
        case .cozy: 4
        case .happy: 5
        }
    }
}

private enum ReviewPosterRenderer {
    static func render(summary: ReviewSummary) -> UIImage {
        let size = CGSize(width: 1400, height: 2100)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            drawGradient(in: rect, colors: [
                UIColor(red: 0.84, green: 0.93, blue: 0.98, alpha: 1),
                UIColor(red: 1.00, green: 0.96, blue: 0.78, alpha: 1),
                UIColor(red: 0.97, green: 0.90, blue: 0.95, alpha: 1)
            ])

            drawDecorations(in: rect)
            let cardRect = CGRect(x: 70, y: 76, width: 1260, height: 1948)
            drawCard(cardRect, radius: 54, fill: UIColor.white.withAlphaComponent(0.9), shadowAlpha: 0.16)

            drawText("WeatherMood365", in: CGRect(x: 120, y: 132, width: 1160, height: 42), font: .systemFont(ofSize: 30, weight: .semibold), color: UIColor.black.withAlphaComponent(0.42), alignment: .center)
            drawText(summary.title, in: CGRect(x: 120, y: 198, width: 1160, height: 88), font: .systemFont(ofSize: 68, weight: .bold), color: .black, alignment: .center)
            drawText("把每天的天气、心情和照片，留成一段可回看的生活。", in: CGRect(x: 160, y: 296, width: 1080, height: 42), font: .systemFont(ofSize: 28, weight: .medium), color: UIColor.black.withAlphaComponent(0.52), alignment: .center)

            drawMetric(title: "记录天数", value: "\(summary.recordedDays)", subtitle: "\(summary.totalDays) 天", rect: CGRect(x: 126, y: 405, width: 360, height: 176))
            drawMetric(title: "记录率", value: "\(summary.recordRate)%", subtitle: "完成度", rect: CGRect(x: 520, y: 405, width: 360, height: 176))
            drawMetric(title: "最常心情", value: summary.topMoodTitle, subtitle: "出现最多", rect: CGRect(x: 914, y: 405, width: 360, height: 176))

            drawSummaryStrip(summary: summary, in: CGRect(x: 126, y: 610, width: 1148, height: 112))
            drawInsight(summary: summary, in: CGRect(x: 126, y: 760, width: 1148, height: 132))
            drawKeywords(summary: summary, in: CGRect(x: 126, y: 916, width: 1148, height: 62))
            drawPhotoGrid(summary: summary, in: CGRect(x: 126, y: 1018, width: 1148, height: 452))
            drawMotivation(summary: summary, in: CGRect(x: 126, y: 1502, width: 1148, height: 68))
            drawNotes(summary: summary, in: CGRect(x: 126, y: 1612, width: 1148, height: 230))
            drawFooter(in: CGRect(x: 126, y: 1880, width: 1148, height: 82))
        }
    }

    private static func drawMetric(title: String, value: String, subtitle: String, rect: CGRect) {
        drawCard(rect, radius: 28, fill: UIColor.white.withAlphaComponent(0.88), shadowAlpha: 0.08)
        drawText(title, in: CGRect(x: rect.minX + 26, y: rect.minY + 24, width: rect.width - 52, height: 34), font: .systemFont(ofSize: 26, weight: .medium), color: UIColor.black.withAlphaComponent(0.46))
        drawText(value, in: CGRect(x: rect.minX + 26, y: rect.minY + 68, width: rect.width - 52, height: 64), font: .systemFont(ofSize: 54, weight: .bold), color: .black)
        drawText(subtitle, in: CGRect(x: rect.minX + 26, y: rect.minY + 132, width: rect.width - 52, height: 28), font: .systemFont(ofSize: 22, weight: .medium), color: UIColor.black.withAlphaComponent(0.38))
    }

    private static func drawSummaryStrip(summary: ReviewSummary, in rect: CGRect) {
        drawCard(rect, radius: 30, fill: UIColor(red: 0.95, green: 0.98, blue: 1, alpha: 0.9), shadowAlpha: 0.06)
        let columnWidth = rect.width / 3
        drawSummaryItem(label: "天气", value: summary.topWeatherTitle, rect: CGRect(x: rect.minX + 28, y: rect.minY + 20, width: columnWidth - 40, height: 72))
        drawSummaryItem(label: "心情", value: summary.topMoodTitle, rect: CGRect(x: rect.minX + columnWidth + 14, y: rect.minY + 20, width: columnWidth - 28, height: 72))
        drawSummaryItem(label: "记录", value: "\(summary.recordedDays) 天", rect: CGRect(x: rect.minX + columnWidth * 2 + 8, y: rect.minY + 20, width: columnWidth - 36, height: 72))
    }

    private static func drawInsight(summary: ReviewSummary, in rect: CGRect) {
        drawCard(rect, radius: 32, fill: UIColor.white.withAlphaComponent(0.88), shadowAlpha: 0.08)
        drawText("智能总结", in: CGRect(x: rect.minX + 32, y: rect.minY + 24, width: 180, height: 34), font: .systemFont(ofSize: 28, weight: .bold), color: .black)
        drawText(summary.insight.summaryText, in: CGRect(x: rect.minX + 32, y: rect.minY + 66, width: rect.width - 64, height: 44), font: .systemFont(ofSize: 24, weight: .regular), color: UIColor.black.withAlphaComponent(0.66), lineLimit: 2)
    }

    private static func drawKeywords(summary: ReviewSummary, in rect: CGRect) {
        let keywords = summary.insight.keywords.prefix(4)
        guard !keywords.isEmpty else { return }
        drawText("关键词", in: CGRect(x: rect.minX, y: rect.minY + 12, width: 96, height: 34), font: .systemFont(ofSize: 24, weight: .bold), color: UIColor.black.withAlphaComponent(0.52))
        var x = rect.minX + 32
        let y = rect.minY + 8
        x += 100
        for keyword in keywords {
            let text = "#\(keyword)"
            let width = min(max(CGFloat(text.count) * 24 + 38, 96), 210)
            drawPill(text, in: CGRect(x: x, y: y, width: width, height: 42))
            x += width + 12
            if x > rect.maxX - 120 { break }
        }
    }

    private static func drawPhotoGrid(summary: ReviewSummary, in rect: CGRect) {
        let photos = summary.featuredPhotoEntries.compactMap { entry -> UIImage? in
            guard let url = summary.imageURLProvider(entry) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }

        drawCard(rect, radius: 34, fill: UIColor.white.withAlphaComponent(0.94), shadowAlpha: 0.1)

        guard !photos.isEmpty else {
            drawText("还没有照片记录", in: rect.insetBy(dx: 40, dy: 330), font: .systemFont(ofSize: 40, weight: .semibold), color: UIColor.black.withAlphaComponent(0.42), alignment: .center)
            return
        }

        let inset: CGFloat = 26
        let gap: CGFloat = 18
        let content = rect.insetBy(dx: inset, dy: inset)
        let columns = 4
        let cellWidth = (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = cellWidth * 4 / 3
        let y = content.midY - cellHeight / 2

        for (offset, image) in photos.prefix(columns).enumerated() {
            let cell = CGRect(
                x: content.minX + CGFloat(offset) * (cellWidth + gap),
                y: y,
                width: cellWidth,
                height: cellHeight
            )
            drawPhoto(image, in: cell, cornerRadius: 24)
        }
    }

    private static func drawMotivation(summary: ReviewSummary, in rect: CGRect) {
        drawCard(rect, radius: 24, fill: UIColor.black.withAlphaComponent(0.055), shadowAlpha: 0)
        drawText(summary.motivationText, in: rect.insetBy(dx: 28, dy: 16), font: .systemFont(ofSize: 24, weight: .semibold), color: UIColor.black.withAlphaComponent(0.56), alignment: .center)
    }

    private static func drawNotes(summary: ReviewSummary, in rect: CGRect) {
        drawText("一句话摘录", in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 54), font: .systemFont(ofSize: 40, weight: .bold), color: .black)
        let notes = Array(summary.noteEntries.prefix(4))
        guard !notes.isEmpty else {
            drawText("这个周期还没有写下一句话。", in: CGRect(x: rect.minX, y: rect.minY + 70, width: rect.width, height: 44), font: .systemFont(ofSize: 28, weight: .medium), color: UIColor.black.withAlphaComponent(0.38))
            return
        }

        for (index, entry) in notes.enumerated() {
            let y = rect.minY + 74 + CGFloat(index) * 52
            let date = entry.date.formatted(.dateTime.month().day())
            drawText("\(date)  \(entry.note)", in: CGRect(x: rect.minX, y: y, width: rect.width, height: 42), font: .systemFont(ofSize: 28, weight: .regular), color: UIColor.black.withAlphaComponent(0.72), lineLimit: 1)
        }
    }

    private static func drawFooter(in rect: CGRect) {
        drawCard(rect, radius: 28, fill: UIColor.black.withAlphaComponent(0.06), shadowAlpha: 0)
        drawText("WeatherMood365", in: CGRect(x: rect.minX + 28, y: rect.minY + 20, width: 360, height: 38), font: .systemFont(ofSize: 30, weight: .bold), color: UIColor.black.withAlphaComponent(0.58))
        drawText("一年里的天气、心情和照片", in: CGRect(x: rect.minX + 390, y: rect.minY + 22, width: rect.width - 420, height: 34), font: .systemFont(ofSize: 24, weight: .medium), color: UIColor.black.withAlphaComponent(0.42), alignment: .right)
    }

    private static func drawPill(_ text: String, in rect: CGRect) {
        UIColor.appAccent.withAlphaComponent(0.12).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        drawText(text, in: rect.insetBy(dx: 14, dy: 7), font: .systemFont(ofSize: 20, weight: .semibold), color: UIColor(red: 0.12, green: 0.34, blue: 0.50, alpha: 1), alignment: .center)
    }

    private static func drawSummaryItem(label: String, value: String, rect: CGRect) {
        drawText(label, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 32), font: .systemFont(ofSize: 28, weight: .semibold), color: UIColor.black.withAlphaComponent(0.42))
        drawText(value, in: CGRect(x: rect.minX, y: rect.minY + 34, width: rect.width, height: 46), font: .systemFont(ofSize: 40, weight: .bold), color: .black)
    }

    private static func drawDecorations(in rect: CGRect) {
        UIColor.white.withAlphaComponent(0.2).setFill()
        UIBezierPath(ovalIn: CGRect(x: -160, y: 120, width: 480, height: 480)).fill()
        UIColor.white.withAlphaComponent(0.22).setFill()
        UIBezierPath(ovalIn: CGRect(x: rect.maxX - 300, y: rect.maxY - 520, width: 520, height: 520)).fill()
    }

    private static func drawPhoto(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        UIGraphicsGetCurrentContext()?.saveGState()
        UIGraphicsGetCurrentContext()?.setShadow(offset: CGSize(width: 0, height: 14), blur: 24, color: UIColor.black.withAlphaComponent(0.16).cgColor)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).fill()
        UIGraphicsGetCurrentContext()?.restoreGState()
        draw(image, aspectFillIn: rect.insetBy(dx: 6, dy: 6), cornerRadius: max(cornerRadius - 4, 8))
    }

    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect, cornerRadius: CGFloat) {
        let imageSize = image.size
        let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        image.draw(in: CGRect(origin: origin, size: size))
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    private static func drawCard(_ rect: CGRect, radius: CGFloat, fill: UIColor, shadowAlpha: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        if shadowAlpha > 0 {
            context?.setShadow(offset: CGSize(width: 0, height: 18), blur: 34, color: UIColor.black.withAlphaComponent(shadowAlpha).cgColor)
        }
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        context?.restoreGState()
    }

    private static func drawGradient(in rect: CGRect, colors: [UIColor]) {
        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: [0, 0.52, 1]
              ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left, lineLimit: Int = 1) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = lineLimit == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        NSString(string: text).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }
}

#Preview {
    ReviewView()
        .environmentObject(EntryStore())
}
