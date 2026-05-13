import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: EntryStore
    @AppStorage(ReminderService.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderService.hourKey) private var reminderHour = 10
    @AppStorage(ReminderService.minuteKey) private var reminderMinute = 30
    @AppStorage(WeatherPhotoLibraryService.syncToLibraryEnabledKey) private var savePhotoCopyToSystemLibrary = false

    @State private var reminderTime = Self.defaultReminderTime()
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var nextReminderDate: Date?
    @State private var isUpdatingReminder = false
    @State private var reminderMessage: String?
    @State private var exportFormat: TextExportFormat = .markdown
    @State private var selectedExportYear: Int?
    @State private var exportDocument = ExportedTextDocument()
    @State private var exportFilename = "WeatherMood365-All.md"
    @State private var exportContentType: UTType = UTType(filenameExtension: "md") ?? .plainText
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var archiveMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("每日提醒") {
                    Toggle("提醒我记录每天", isOn: reminderBinding)
                        .disabled(isUpdatingReminder)

                    DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .disabled(!reminderEnabled || isUpdatingReminder)
                        .onChange(of: reminderTime) { _, newValue in
                            updateReminderTime(newValue)
                        }

                    LabeledContent("通知权限") {
                        Text(permissionText)
                            .foregroundStyle(permissionColor)
                    }

                    if reminderEnabled, let nextReminderDate {
                        LabeledContent("下一次提醒") {
                            Text(nextReminderDate, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("如果当天已经有记录，WeatherMood365 会把提醒顺延到下一天。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let reminderMessage {
                        Text(reminderMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("导入导出") {
                    Picker("导出格式", selection: $exportFormat) {
                        ForEach(TextExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: exportFormat) { _, _ in
                        updateExportMetadata()
                    }

                    Picker("导出范围", selection: $selectedExportYear) {
                        Text("全部记录").tag(Int?.none)
                        ForEach(availableYears, id: \.self) { year in
                            Text(verbatim: "\(String(year))年").tag(Optional(year))
                        }
                    }
                    .onChange(of: selectedExportYear) { _, _ in
                        updateExportMetadata()
                    }

                    Button {
                        prepareExport()
                    } label: {
                        Label("导出 \(exportFormat.title)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(exportEntries.isEmpty)

                    if exportFormat == .json {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("导入 JSON", systemImage: "square.and.arrow.down")
                        }
                    }

                    Text("Markdown 适合阅读和交给 AI 分析；JSON 可用于备份和恢复文字记录，不包含照片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if exportEntries.isEmpty {
                        Text("还没有可导出的记录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let archiveMessage {
                        Text(archiveMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("照片") {
                    Toggle("拍照后同步到系统相册", isOn: $savePhotoCopyToSystemLibrary)

                    Text("开启后，仅通过 App 内拍照新增或更新的照片会尝试额外保存到系统相册，再归档进 WeatherMood365 专用相簿。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("选择系统相册照片需要读取权限；自动同步到系统相册和专用相簿还需要额外写入能力。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("从系统相册挑选的旧照片不会再次写回相册，避免重复保存和额外权限风险。即使同步失败，记录本身也会保存在 App 内。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本") {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Text("更多设置会陆续放在这里，比如备份、导出和隐私选项。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                archiveMessage = "导出成功：\(exportFilename)"
            case .failure(let error):
                archiveMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json]
        ) { result in
            importJSON(from: result)
        }
        .task {
            reminderTime = dateForStoredReminderTime()
            updateExportMetadata()
            await refreshReminderState()
        }
        .onChange(of: store.version) { _, _ in
            guard reminderEnabled else { return }
            Task {
                await ReminderService.shared.syncReminder(with: store)
                await refreshReminderState()
            }
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding {
            reminderEnabled
        } set: { newValue in
            Task {
                await setReminderEnabled(newValue)
            }
        }
    }

    private var permissionText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "已允许"
        case .denied:
            "已关闭"
        case .notDetermined:
            "尚未请求"
        @unknown default:
            "未知"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            .green
        case .denied:
            .red
        default:
            .secondary
        }
    }

    private var availableYears: [Int] {
        let years = Set(store.sortedEntries.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    private var exportEntries: [DailyEntry] {
        store.sortedEntries
            .filter { entry in
                guard let selectedExportYear else { return true }
                return Calendar.current.component(.year, from: entry.date) == selectedExportYear
            }
            .sorted { $0.date < $1.date }
    }

    private var exportScopeTitle: String {
        if let selectedExportYear {
            "\(String(selectedExportYear))年"
        } else {
            "全部记录"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
    }

    private func setReminderEnabled(_ enabled: Bool) async {
        isUpdatingReminder = true
        reminderMessage = nil

        defer {
            isUpdatingReminder = false
        }

        if enabled {
            do {
                let granted = try await ReminderService.shared.enableReminder(with: store)
                reminderEnabled = granted
                reminderMessage = granted ? "提醒已开启。" : "没有通知权限，提醒未开启。"
            } catch {
                reminderEnabled = false
                reminderMessage = "通知权限请求失败：\(error.localizedDescription)"
            }
        } else {
            ReminderService.shared.disableReminder()
            reminderMessage = "提醒已关闭。"
        }

        await refreshReminderState()
    }

    private func updateReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = components.hour ?? 10
        reminderMinute = components.minute ?? 30

        guard reminderEnabled else { return }
        Task {
            await ReminderService.shared.syncReminder(with: store)
            await refreshReminderState()
        }
    }

    private func refreshReminderState() async {
        authorizationStatus = await ReminderService.shared.authorizationStatus()
        nextReminderDate = await ReminderService.shared.nextPendingReminderDate()
    }

    private func prepareExport() {
        do {
            let text = try TextArchiveService.exportText(
                entries: exportEntries,
                format: exportFormat,
                scopeTitle: exportScopeTitle
            )
            updateExportMetadata()
            exportDocument = ExportedTextDocument(text: text)
            archiveMessage = nil
            isExporterPresented = true
        } catch {
            archiveMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func updateExportMetadata() {
        let scope = selectedExportYear.map(String.init) ?? "All"
        exportFilename = "WeatherMood365-\(scope).\(exportFormat.fileExtension)"
        exportContentType = exportFormat.contentType
    }

    private func importJSON(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let archive = try TextArchiveService.decodeArchive(from: data)
            let importResult = store.importTextArchive(archive)
            archiveMessage = "导入完成：新增 \(importResult.added) 条，更新 \(importResult.updated) 条，跳过 \(importResult.skipped) 条。"
        } catch {
            archiveMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func dateForStoredReminderTime() -> Date {
        Calendar.current.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: Date()
        ) ?? Self.defaultReminderTime()
    }

    private static func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: Date()) ?? Date()
    }
}

#Preview {
    SettingsView()
        .environmentObject(EntryStore())
}
