import SwiftUI

struct YearCalendarView: View {
    @EnvironmentObject private var store: EntryStore

    let targetDate: Date
    let jumpToken: Int

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        yearProgress

                        ForEach(monthsInCurrentYear, id: \.self) { month in
                            MonthCalendarView(
                                month: month,
                                monthEntries: monthEntriesByIdentifier[monthIdentifier(for: month)] ?? [],
                                refreshToken: store.version
                            )
                                .id(monthIdentifier(for: month))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .onAppear {
                    scrollToTargetMonth(with: reader, animated: false)
                }
                .onChange(of: jumpToken) { _, _ in
                    scrollToTargetMonth(with: reader, animated: true)
                }
            }
            .navigationTitle("年度日历")
        }
    }

    private var yearProgress: some View {
        let year = calendar.component(.year, from: Date())
        let total = daysInCurrentYear.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(year)")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Text("\(store.entries.count)/\(total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(store.entries.count), total: Double(max(total, 1)))
        }
    }

    private var monthsInCurrentYear: [Date] {
        let year = calendar.component(.year, from: Date())
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    private var daysInCurrentYear: [Date] {
        guard let firstMonth = monthsInCurrentYear.first,
              let range = calendar.range(of: .day, in: .year, for: firstMonth) else {
            return []
        }

        return range.compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 1, to: firstMonth)
        }
    }

    private var monthEntriesByIdentifier: [String: [DailyEntry]] {
        Dictionary(grouping: store.sortedEntries) { entry in
            monthIdentifier(for: entry.date)
        }
    }

    private func scrollToTargetMonth(with reader: ScrollViewProxy, animated: Bool) {
        let identifier = monthIdentifier(for: targetDate)

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.28)) {
                    reader.scrollTo(identifier, anchor: .top)
                }
            } else {
                reader.scrollTo(identifier, anchor: .top)
            }
        }
    }

    private func monthIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}

private struct MonthCalendarView: View {
    let month: Date
    let monthEntries: [DailyEntry]
    let refreshToken: Int

    private let calendar = Calendar.current
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(month, format: .dateTime.month(.wide))
                    .font(.title3.weight(.semibold))

                Spacer()

                if !monthEntries.isEmpty {
                    NavigationLink {
                        MonthEntriesView(month: month)
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看全部 \(monthEntries.count) 条")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            GeometryReader { proxy in
                let cellSize = max(44, (proxy.size.width - spacing * 6) / 7)
                let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 7)
                let entriesByDay = entriesByDayMap

                LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize, height: 20)
                    }

                    ForEach(monthCells, id: \.self) { date in
                        if let date {
                            NavigationLink {
                                EntryDetailView(date: date)
                            } label: {
                                dayCell(for: date, entriesByDay: entriesByDay, size: cellSize)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
            .frame(height: monthGridHeight)
        }
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var entriesByDayMap: [Date: DailyEntry] {
        monthEntries.reduce(into: [:]) { result, entry in
            result[calendar.startOfDay(for: entry.date)] = entry
        }
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }

        let prefix = calendar.component(.weekday, from: firstDay) - 1
        let days = range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        }

        return Array(repeating: nil, count: prefix) + days
    }

    private var monthGridHeight: CGFloat {
        let rows = ceil(Double(monthCells.count) / 7.0)
        return 20 + spacing + CGFloat(rows) * 52 + CGFloat(max(rows - 1, 0)) * spacing
    }

    private func dayCell(for date: Date, entriesByDay: [Date: DailyEntry], size: CGFloat) -> some View {
        let entry = entriesByDay[calendar.startOfDay(for: date)]
        let isToday = calendar.isDateInToday(date)
        let photoURL = entry.flatMap { imageURL(for: $0) }
        let hasPhoto = photoURL != nil

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(for: entry, isToday: isToday))

            if let photoURL {
                CachedPhotoView(
                    url: photoURL,
                    targetSize: CGSize(width: size, height: size),
                    contentMode: .fill,
                    refreshToken: refreshToken
                ) {
                    backgroundColor(for: entry, isToday: isToday)
                }
                .frame(width: size, height: size)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.12), .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isToday || entry != nil ? .bold : .regular))
                    .monospacedDigit()

                Spacer(minLength: 0)

                if let entry {
                    Text(entry.weather?.summary ?? entry.mood.title)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(entry.mood.title)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(5)
            .foregroundStyle(textColor(for: entry, hasPhoto: hasPhoto))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(for: entry, isToday: isToday, hasPhoto: hasPhoto), lineWidth: borderWidth(for: entry, isToday: isToday, hasPhoto: hasPhoto))
        }
        .accessibilityLabel(accessibilityLabel(for: date, entry: entry))
    }

    private func imageURL(for entry: DailyEntry) -> URL? {
        guard let photoFilename = entry.photoFilename else { return nil }
        return documentsDirectory
            .appendingPathComponent("Photos", isDirectory: true)
            .appendingPathComponent(photoFilename)
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func backgroundColor(for entry: DailyEntry?, isToday: Bool) -> Color {
        guard let entry else {
            return isToday ? .blue.opacity(0.12) : .secondary.opacity(0.1)
        }

        switch entry.mood {
        case .happy: return Color.yellow.opacity(0.85)
        case .plain: return Color.gray.opacity(0.75)
        case .cozy: return Color.green.opacity(0.75)
        case .irritated: return Color.orange.opacity(0.8)
        case .low: return Color.indigo.opacity(0.75)
        }
    }

    private func borderColor(for entry: DailyEntry?, isToday: Bool, hasPhoto: Bool) -> Color {
        if isToday { return .blue }
        if hasPhoto { return .white.opacity(0.9) }
        if entry != nil { return .blue.opacity(0.55) }
        return .clear
    }

    private func borderWidth(for entry: DailyEntry?, isToday: Bool, hasPhoto: Bool) -> CGFloat {
        if isToday { return 2.5 }
        if hasPhoto || entry != nil { return 1.5 }
        return 0
    }

    private func textColor(for entry: DailyEntry?, hasPhoto: Bool) -> Color {
        if hasPhoto { return .white }
        if entry?.mood == .happy { return .black }
        if entry != nil { return .white }
        return .primary
    }

    private func accessibilityLabel(for date: Date, entry: DailyEntry?) -> String {
        let day = date.formatted(.dateTime.month().day())
        if let entry {
            let weather = entry.weather?.summary ?? "无天气"
            return "\(day)，\(weather)，\(entry.mood.title)"
        }
        return "\(day)，未记录"
    }
}

private struct MonthPreviewEntryCard: View {
    let entry: DailyEntry

    private var imageURL: URL? {
        guard let photoFilename = entry.photoFilename else { return nil }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
            .appendingPathComponent(photoFilename)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoPreview

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.date, format: .dateTime.month().day())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 7) {
                    if let weather = entry.weather {
                        Label(weather.summary, systemImage: weather.symbol)
                    } else {
                        Label("无天气", systemImage: "cloud")
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.secondary)

                MoodTextView(mood: entry.mood, iconSize: 15)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(entry.date.formatted(.dateTime.month().day()))，\(entry.weather?.summary ?? "无天气")，\(entry.mood.title)")
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let imageURL {
            ZStack {
                Color.secondary.opacity(0.10)

                CachedPhotoView(
                    url: imageURL,
                    targetSize: CGSize(width: 360, height: 480),
                    contentMode: .fit
                ) {
                    Color.secondary.opacity(0.10)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()
        } else {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    private var backgroundColors: [Color] {
        switch entry.mood {
        case .happy: return [.yellow, .orange]
        case .plain: return [.gray, .blue.opacity(0.65)]
        case .cozy: return [.green, .teal]
        case .irritated: return [.orange, .red]
        case .low: return [.indigo, .blue]
        }
    }
}

private struct MonthEntriesView: View {
    @EnvironmentObject private var store: EntryStore

    let month: Date

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(entries) { entry in
                    NavigationLink {
                        EntryDetailView(date: entry.date)
                    } label: {
                        MonthPreviewEntryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthTitle: String {
        let monthNumber = calendar.component(.month, from: month)
        return "\(monthNumber)月记录"
    }

    private var entries: [DailyEntry] {
        store.sortedEntries.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
}
