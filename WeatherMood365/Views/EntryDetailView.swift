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
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(weather.summary) \(weather.temperature, specifier: "%.0f")°C")
                                    .font(.headline)
                            }
                        } icon: {
                            Image(systemName: weather.symbol)
                                .foregroundStyle(.blue)
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
        .navigationTitle(date.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isEditorActive) {
            if let entry {
                EntryEditorView(entry: entry, allowsDateEditing: false, titleOverride: "修改记录")
            }
        }
        .overlay {
            if isDeleteConfirmationPresented, let entry {
                DeleteConfirmationOverlay(
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isDeleteConfirmationPresented = false
                        }
                    },
                    onDelete: {
                        store.delete(entry)
                        dismiss()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
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

    @MainActor
    private func loadDetailImage() async {
        guard let url = detailImageURL else {
            detailImage = nil
            return
        }

        let loadedImage = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value

        guard detailImageURL == url else { return }
        detailImage = loadedImage
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
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    ZStack {
                        if let renderedPreview {
                            Image(uiImage: renderedPreview)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
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
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
                        )
                }
                .buttonStyle(.plain)
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原图"
        case .polaroid: "拍立得"
        case .colorwalk: "Colorwalk"
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

    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect) {
        let imageSize = image.size
        let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        UIGraphicsGetCurrentContext()?.saveGState()
        let clippingPath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
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

private struct DeleteConfirmationOverlay: View {
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isDeleting = false
    @State private var isContentVisible = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isDeleting else { return }
                    onCancel()
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("删除这条记录？")
                        .font(.title3.weight(.semibold))

                    Text("删除后，照片、天气和心情都会从这一天移除。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                HStack(spacing: 10) {
                    Button {
                        onCancel()
                    } label: {
                        Text("取消")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .foregroundStyle(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.secondary.opacity(0.24), lineWidth: 1)
                    }

                    Button(role: .destructive) {
                        deleteWithFeedback()
                    } label: {
                        ZStack {
                            Text("删除")
                                .opacity(isDeleting ? 0 : 1)

                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.red)
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(.horizontal, 24)
            .scaleEffect(isContentVisible ? 1 : 0.94)
            .opacity(isContentVisible ? 1 : 0)
        }
    }

    private func deleteWithFeedback() {
        guard !isDeleting else { return }
        isDeleting = true
        withAnimation(.easeInOut(duration: 0.18)) {
            isContentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            onDelete()
        }
    }
}

private struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}
