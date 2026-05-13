import CoreImage
import CoreLocation
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EntryStore

    let date: Date
    @State private var isImagePreviewPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditorActive = false
    @State private var isExportSheetPresented = false
    @State private var saveMessage: String?
    @State private var resolvedLocationText: String?
    @State private var detailImage: UIImage?
    @State private var isDeletingEntry = false
    @State private var isBackfillingWeatherDetails = false

    private var entry: DailyEntry? {
        store.entry(for: date)
    }

    private var detailImageURL: URL? {
        guard let entry,
              let url = store.imageURL(for: entry) else { return nil }
        return url
    }

    var body: some View {
        List {
            if let entry {
                Section {
                    if let image = detailImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 180, maxHeight: 420)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                isImagePreviewPresented = true
                            }
                    }

                    MoodTextView(mood: entry.mood, iconSize: 22)
                        .font(.headline)

                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(.body)
                    }
                }

                if let weather = entry.weather {
                    Section("天气") {
                        VStack(alignment: .leading, spacing: 14) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(weather.summary) \(weather.temperature, specifier: "%.0f")°C")
                                        .font(.headline)
                                }
                            } icon: {
                                Image(systemName: weather.symbol)
                                    .foregroundStyle(.blue)
                            }

                            Divider()

                            WeatherDetailMetricsView(weather: weather, isRefreshing: isBackfillingWeatherDetails)
                        }
                    }
                }

                if let location = entry.photoLocation {
                    Section("位置") {
                        Label(location.name ?? resolvedLocationText ?? location.displayText, systemImage: "location.fill")
                            .font(.headline)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        Label("删除这条记录", systemImage: "trash")
                    }
                }
            } else {
                ContentUnavailableView(
                    "这一天还没有记录",
                    systemImage: "calendar",
                    description: Text("回到今天页面添加照片、心情和天气。")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .opacity(isDeletingEntry ? 0 : 1)
        .scaleEffect(isDeletingEntry ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.2), value: isDeletingEntry)
        .allowsHitTesting(!isDeletingEntry)
        .navigationTitle(date.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isEditorActive) {
            if let entry {
                EntryEditorView(entry: entry, allowsDateEditing: false, titleOverride: "修改记录")
            }
        }
        .alert("删除这条记录？", isPresented: $isDeleteConfirmationPresented) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let entry = store.entry(for: date) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDeletingEntry = true
                    }
                    store.delete(entry)
                    dismiss()
                }
            }
        } message: {
            Text("删除后，照片、天气和心情都会从这一天移除。")
        }
        .toolbar {
            if entry != nil || detailImage != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if entry != nil {
                        Button {
                            isEditorActive = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("修改记录")
                    }

                    if detailImage != nil {
                        Button {
                            isExportSheetPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("导出照片")
                    }
                }
            }
        }
        .task(id: entry?.id) {
            guard let location = entry?.photoLocation, location.name == nil else {
                resolvedLocationText = nil
                return
            }

            resolvedLocationText = await placeName(for: CLLocation(latitude: location.latitude, longitude: location.longitude))
        }
        .task(id: entry?.photoFilename) {
            await loadDetailImage()
        }
        .task(id: weatherBackfillTaskID) {
            await backfillWeatherDetailsIfNeeded()
        }
        .sheet(isPresented: $isExportSheetPresented) {
            if let entry, let image = detailImage {
                ExportPhotoView(entry: entry, image: image) { exportedImage in
                    UIImageWriteToSavedPhotosAlbum(exportedImage, nil, nil, nil)
                    saveMessage = "已导出到相册。"
                    isExportSheetPresented = false
                }
                .presentationDetents([.large])
            }
        }
        .fullScreenCover(isPresented: $isImagePreviewPresented) {
            if let image = detailImage {
                ImagePreviewView(image: image)
            }
        }
        .alert("照片", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(saveMessage ?? "")
        }
    }

    private var weatherBackfillTaskID: String {
        guard let entry else { return "empty" }
        let signature = entry.weather.map {
            "\($0.fetchedAt.timeIntervalSince1970)-\($0.visibility ?? -1)-\($0.aqi ?? -1)-\($0.aerosolOpticalDepth ?? -1)"
        } ?? "no-weather"
        return "\(entry.id.uuidString)-\(signature)"
    }

    private func loadDetailImage() async {
        guard let url = detailImageURL else {
            detailImage = nil
            return
        }

        let screenWidth = UIScreen.main.bounds.width
        let targetSize = CGSize(width: screenWidth, height: 420)
        let loadedImage = await PhotoImageCache.shared.image(for: url, targetSize: targetSize, scale: UIScreen.main.scale)

        guard detailImageURL == url else { return }
        detailImage = loadedImage
    }

    @MainActor
    private func backfillWeatherDetailsIfNeeded() async {
        guard let entry,
              let weather = entry.weather,
              weather.needsDetailBackfill,
              let location = entry.photoLocation,
              !isBackfillingWeatherDetails else {
            return
        }

        isBackfillingWeatherDetails = true
        defer { isBackfillingWeatherDetails = false }

        do {
            let refreshedWeather = try await WeatherService().weather(
                for: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            )
            var updatedEntry = entry
            updatedEntry.weather = WeatherSnapshot(
                temperature: weather.temperature,
                windSpeed: weather.windSpeed,
                weatherCode: weather.weatherCode,
                fetchedAt: weather.fetchedAt,
                visibility: refreshedWeather.visibility,
                aqi: refreshedWeather.aqi,
                aerosolOpticalDepth: refreshedWeather.aerosolOpticalDepth
            )
            _ = try? await store.upsert(updatedEntry, imageData: nil)
        } catch {
            // Keep detail view quiet if only the supplemental metrics fail.
        }
    }

}

private struct WeatherDetailMetricsView: View {
    let weather: WeatherSnapshot
    let isRefreshing: Bool

    var body: some View {
        VStack(spacing: 10) {
            LabeledContent("AQI") {
                Text(weather.aqiText)
                    .foregroundStyle(metricColor(weather.aqi))
            }

            LabeledContent("能见度") {
                Text(weather.visibilityText)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("AOD 气溶胶") {
                Text(weather.aerosolOpticalDepthText)
                    .foregroundStyle(.secondary)
            }

            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在补全天气细节...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func metricColor(_ aqi: Double?) -> Color {
        guard let aqi else { return .secondary }
        switch aqi {
        case ..<20: return Color.green
        case ..<40: return Color.mint
        case ..<60: return Color.yellow
        case ..<80: return Color.orange
        case ..<100: return Color.red
        default: return Color.purple
        }
    }
}

private struct ExportPhotoView: View {
    let entry: DailyEntry
    let image: UIImage
    let onExport: (UIImage) -> Void

    @State private var selectedStyle: ExportStyle = .original
    @State private var renderedPreview: UIImage?
    @State private var isRenderingPreview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("导出样式", selection: $selectedStyle) {
                    ForEach(ExportStyle.allCases) { style in
                        Text(style.title)
                            .tag(style)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)

                ScrollView {
                    ZStack {
                        if let renderedPreview {
                            Image(uiImage: renderedPreview)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.standard))
                                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                        }

                        if isRenderingPreview {
                            ProgressView()
                                .padding(18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }

                Button {
                    if let renderedPreview {
                        onExport(renderedPreview)
                    }
                } label: {
                    Label("导出到相册", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.primary)
                                .fill(Color.brandYellow)
                        )
                }
                .buttonStyle(.pressableCard(cornerRadius: AppRadius.primary, pressedScale: 0.98, overlayColor: .black.opacity(0.1)))
                .disabled(renderedPreview == nil || isRenderingPreview)
                .opacity(renderedPreview == nil || isRenderingPreview ? 0.55 : 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("导出预览")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                renderPreview(for: selectedStyle)
            }
            .onChange(of: selectedStyle) { _, newValue in
                renderPreview(for: newValue)
            }
        }
    }

    private func renderPreview(for style: ExportStyle) {
        isRenderingPreview = style != .original
        if style == .original {
            renderedPreview = image
            return
        }

        let entry = entry
        let image = image
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered: UIImage
            switch style {
            case .original:
                rendered = image
            case .polaroid:
                rendered = ExportImageRenderer.polaroid(image: image, entry: entry)
            case .colorwalk:
                rendered = ExportImageRenderer.colorwalk(image: image, entry: entry)
            case .postcard:
                rendered = ExportImageRenderer.postcard(image: image, entry: entry)
            case .film:
                rendered = ExportImageRenderer.film(image: image, entry: entry)
            }

            DispatchQueue.main.async {
                guard selectedStyle == style else { return }
                renderedPreview = rendered
                isRenderingPreview = false
            }
        }
    }
}

private enum ExportStyle: String, CaseIterable, Identifiable {
    case original
    case polaroid
    case colorwalk
    case postcard
    case film

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原图"
        case .polaroid: "拍立得"
        case .colorwalk: "Colorwalk"
        case .postcard: "天气明信片"
        case .film: "胶片边框"
        }
    }
}

private enum ExportImageRenderer {
    private static let colorContext = CIContext(options: [.workingColorSpace: kCFNull as Any])

    static func polaroid(image: UIImage, entry: DailyEntry) -> UIImage {
        let size = CGSize(width: 1500, height: 2000)
        let paperRect = CGRect(x: 150, y: 120, width: 1200, height: 1640)
        let photoRect = CGRect(x: paperRect.minX + 82, y: paperRect.minY + 82, width: paperRect.width - 164, height: 1120)
        let captionRect = CGRect(x: paperRect.minX + 95, y: photoRect.maxY + 72, width: paperRect.width - 190, height: 230)

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.92, green: 0.93, blue: 0.94, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: -0.035)
            context.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)

            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 28),
                blur: 42,
                color: UIColor.black.withAlphaComponent(0.28).cgColor
            )
            UIColor.white.setFill()
            UIBezierPath(roundedRect: paperRect, cornerRadius: 28).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill()
            UIBezierPath(roundedRect: photoRect, cornerRadius: 8).fill()
            draw(image, aspectFillIn: photoRect)
            drawPolaroidCaption(for: entry, in: captionRect)
            context.cgContext.restoreGState()
        }
    }

    static func colorwalk(image: UIImage, entry: DailyEntry) -> UIImage {
        let side: CGFloat = 1600
        let dominant = image.averageColor(using: colorContext) ?? UIColor.systemBlue
        let border: CGFloat = 130
        let captionHeight: CGFloat = 210
        let size = CGSize(width: side, height: side)
        let photoSide = side - border * 2 - captionHeight
        let photoRect = CGRect(x: (side - photoSide) / 2, y: border, width: photoSide, height: photoSide)
        let captionRect = CGRect(x: border, y: photoRect.maxY + 44, width: side - border * 2, height: captionHeight - 70)

        return UIGraphicsImageRenderer(size: size).image { context in
            dominant.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            dominant.setFill()
            UIBezierPath(roundedRect: photoRect, cornerRadius: 24).fill()
            draw(image, aspectFillIn: photoRect)
            drawColorwalkCaption(for: entry, in: captionRect, textColor: dominant.readableTextColor)
        }
    }

    static func postcard(image: UIImage, entry: DailyEntry) -> UIImage {
        let size = CGSize(width: 1800, height: 1200)
        let margin: CGFloat = 86
        let photoRect = CGRect(x: margin, y: margin, width: 1060, height: size.height - margin * 2)
        let textRect = CGRect(x: photoRect.maxX + 76, y: margin + 34, width: size.width - photoRect.maxX - margin - 76, height: size.height - margin * 2 - 68)

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1).setStroke()
            UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: 36, y: 36), size: CGSize(width: size.width - 72, height: size.height - 72)), cornerRadius: 12).stroke()

            draw(image, aspectFillIn: photoRect, cornerRadius: 10)
            drawPostcardCaption(for: entry, in: textRect)
        }
    }

    static func film(image: UIImage, entry: DailyEntry) -> UIImage {
        let size = CGSize(width: 1600, height: 2000)
        let frameRect = CGRect(x: 110, y: 96, width: size.width - 220, height: size.height - 192)
        let photoRect = frameRect.insetBy(dx: 96, dy: 140)

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            drawFilmPerforations(in: frameRect)
            draw(image, aspectFillIn: photoRect, cornerRadius: 4)

            let captionRect = CGRect(x: photoRect.minX, y: photoRect.maxY + 42, width: photoRect.width, height: 120)
            drawFilmCaption(for: entry, in: captionRect)
        }
    }

    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect, cornerRadius: CGFloat = 8) {
        let imageSize = image.size
        let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        UIGraphicsGetCurrentContext()?.saveGState()
        let clippingPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        clippingPath.addClip()
        image.draw(in: CGRect(origin: origin, size: size))
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    private static func drawPolaroidCaption(for entry: DailyEntry, in rect: CGRect) {
        let date = entry.date.formatted(.dateTime.year().month().day())
        let weatherText = entry.weather.map {
            "\($0.summary) \($0.temperature.formatted(.number.precision(.fractionLength(0))))°C"
        }
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)

        drawText(
            date,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 64),
            font: UIFont.systemFont(ofSize: 54, weight: .semibold),
            color: .black
        )

        if let weatherText {
            drawText(
                weatherText,
                in: CGRect(x: rect.minX, y: rect.minY + 76, width: rect.width, height: 50),
                font: UIFont.systemFont(ofSize: 36, weight: .medium),
                color: UIColor.black.withAlphaComponent(0.72)
            )
        }

        if !note.isEmpty {
            drawText(
                note,
                in: CGRect(x: rect.minX, y: rect.minY + 136, width: rect.width, height: rect.height - 136),
                font: UIFont.systemFont(ofSize: 34, weight: .regular),
                color: UIColor.black.withAlphaComponent(0.78),
                lineLimit: 2
            )
        }
    }

    private static func drawColorwalkCaption(for entry: DailyEntry, in rect: CGRect, textColor: UIColor) {
        let date = entry.date.formatted(.dateTime.year().month().day())
        let location = entry.photoLocation?.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        drawText(
            date,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 64),
            font: UIFont.systemFont(ofSize: 54, weight: .semibold),
            color: textColor
        )

        if let location, !location.isEmpty {
            drawText(
                location,
                in: CGRect(x: rect.minX, y: rect.minY + 78, width: rect.width, height: 52),
                font: UIFont.systemFont(ofSize: 36, weight: .medium),
                color: textColor.withAlphaComponent(0.82),
                lineLimit: 1
            )
        }
    }

    private static func drawPostcardCaption(for entry: DailyEntry, in rect: CGRect) {
        let date = entry.date.formatted(.dateTime.year().month().day().weekday())
        let weatherText = entry.weather.map {
            "\($0.summary)  \($0.temperature.formatted(.number.precision(.fractionLength(0))))°C"
        } ?? "WeatherMood365"
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)

        drawText(
            date,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 72),
            font: UIFont.systemFont(ofSize: 48, weight: .semibold),
            color: UIColor(red: 0.18, green: 0.22, blue: 0.25, alpha: 1)
        )
        drawText(
            weatherText,
            in: CGRect(x: rect.minX, y: rect.minY + 96, width: rect.width, height: 58),
            font: UIFont.systemFont(ofSize: 34, weight: .medium),
                            color: UIColor.appAccent
        )

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: rect.minX, y: rect.minY + 190))
        linePath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 190))
        UIColor(red: 0.82, green: 0.78, blue: 0.69, alpha: 1).setStroke()
        linePath.lineWidth = 2
        linePath.stroke()

        if !note.isEmpty {
            drawText(
                note,
                in: CGRect(x: rect.minX, y: rect.minY + 230, width: rect.width, height: 260),
                font: UIFont.systemFont(ofSize: 36, weight: .regular),
                color: UIColor.black.withAlphaComponent(0.74),
                lineLimit: 4
            )
        }

        drawText(
            entry.mood.title,
            in: CGRect(x: rect.minX, y: rect.maxY - 82, width: rect.width, height: 60),
            font: UIFont.systemFont(ofSize: 34, weight: .semibold),
            color: UIColor.black.withAlphaComponent(0.62)
        )
    }

    private static func drawFilmCaption(for entry: DailyEntry, in rect: CGRect) {
        let date = entry.date.formatted(.dateTime.year().month().day())
        let weatherText = entry.weather.map { "  \($0.summary)" } ?? ""
        drawText(
            "\(date)\(weatherText)",
            in: rect,
            font: UIFont.monospacedSystemFont(ofSize: 32, weight: .medium),
            color: UIColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1)
        )
    }

    private static func drawFilmPerforations(in rect: CGRect) {
        UIColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 1).setFill()
        let holeSize = CGSize(width: 54, height: 36)
        let rows = 14
        for index in 0..<rows {
            let y = rect.minY + 44 + CGFloat(index) * ((rect.height - 88) / CGFloat(rows - 1))
            UIBezierPath(roundedRect: CGRect(x: rect.minX + 16, y: y, width: holeSize.width, height: holeSize.height), cornerRadius: 7).fill()
            UIBezierPath(roundedRect: CGRect(x: rect.maxX - 16 - holeSize.width, y: y, width: holeSize.width, height: holeSize.height), cornerRadius: 7).fill()
        }
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        lineLimit: Int = 1
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineLimit == 1 ? .byTruncatingTail : .byTruncatingTail
        paragraph.maximumLineHeight = font.lineHeight * 1.12
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}

private extension UIImage {
    func averageColor(using context: CIContext) -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let outputImage = filter?.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

private extension UIColor {
    var readableTextColor: UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.58 ? .black : .white
    }

    var adjustedForPhotoMatte: UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return UIColor(
            red: min(red + 0.12, 1),
            green: min(green + 0.12, 1),
            blue: min(blue + 0.12, 1),
            alpha: 0.82
        )
    }
}

