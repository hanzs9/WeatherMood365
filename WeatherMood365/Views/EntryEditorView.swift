import CoreLocation
import SwiftUI

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EntryStore

    @State private var entry: DailyEntry
    @State private var selectedImageData: Data?
    @State private var isCameraPresented = false
    @State private var isPhotoLibraryPresented = false
    @State private var weatherStatus = "尚未获取天气"
    @State private var isFetchingWeather = false
    @State private var errorMessage: String?
    @State private var didAutoFetchWeather = false
    @State private var didFetchInitialPhotoLocation = false
    @State private var selectedManualWeatherCode = -1

    private let allowsDateEditing: Bool
    private let titleOverride: String?
    private let shouldFetchCurrentLocationForInitialPhoto: Bool

    init(
        entry: DailyEntry,
        initialImageData: Data? = nil,
        initialPickedPhoto: PickedPhoto? = nil,
        shouldFetchCurrentLocationForInitialPhoto: Bool = false,
        allowsDateEditing: Bool = true,
        titleOverride: String? = nil
    ) {
        var initialEntry = entry
        let pickedPhotoData = initialPickedPhoto?.data ?? initialImageData
        if let date = initialPickedPhoto?.date, allowsDateEditing {
            initialEntry.date = date
        }
        if let location = initialPickedPhoto?.location {
            initialEntry.photoLocation = location
        }

        _entry = State(initialValue: initialEntry)
        _selectedImageData = State(initialValue: pickedPhotoData)
        _selectedManualWeatherCode = State(initialValue: entry.weather?.weatherCode ?? -1)
        self.allowsDateEditing = allowsDateEditing
        self.titleOverride = titleOverride
        self.shouldFetchCurrentLocationForInitialPhoto = shouldFetchCurrentLocationForInitialPhoto
        if let weather = entry.weather {
            _weatherStatus = State(initialValue: "\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C")
        }
    }

    var body: some View {
        Form {
            Section("日期") {
                if allowsDateEditing {
                    DatePicker("记录日期", selection: $entry.date, displayedComponents: .date)
                } else {
                    LabeledContent("记录日期") {
                        Text(entry.date, format: .dateTime.year().month().day().weekday())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("照片") {
                HStack(spacing: 10) {
                    Button {
                        isCameraPresented = true
                    } label: {
                        PhotoSourceButton(title: "拍照", systemImage: "camera.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        isPhotoLibraryPresented = true
                    } label: {
                        PhotoSourceButton(title: "相册", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                }

                photoPreview
            }

            Section("心情") {
                HStack(spacing: 8) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            entry.mood = mood
                        } label: {
                            VStack(spacing: 5) {
                                MoodIconView(mood: mood, size: 24)
                                Text(mood.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(entry.mood == mood ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(entry.mood == mood ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(entry.mood == mood ? Color.blue.opacity(0.55) : .clear, lineWidth: 1.4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("今天一句话") {
                TextField("比如：今天的风很轻，心也慢了下来。", text: $entry.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("天气") {
                Picker("天气情况", selection: $selectedManualWeatherCode) {
                    Text("自动获取").tag(-1)
                    ForEach(manualWeatherOptions, id: \.code) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option.code)
                    }
                }
                .onChange(of: selectedManualWeatherCode) { _, newValue in
                    applyManualWeather(code: newValue)
                }

                HStack(spacing: 12) {
                    if let weather = entry.weather {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C")
                                    .font(.headline)
                            }
                        } icon: {
                            Image(systemName: weather.symbol)
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Text(weatherStatus)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        fetchWeather()
                    } label: {
                        if isFetchingWeather {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isFetchingWeather)
                    .accessibilityLabel("重新获取天气")
                }
            }

            if let location = entry.photoLocation {
                Section("位置") {
                    Label(location.name ?? location.displayText, systemImage: "location.fill")
                        .font(.headline)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.upsert(entry, imageData: selectedImageData)
                    dismiss()
                }
            }
        }
        .task {
            guard entry.weather == nil, !didAutoFetchWeather else { return }
            didAutoFetchWeather = true
            fetchWeather()
        }
        .task {
            guard shouldFetchCurrentLocationForInitialPhoto,
                  selectedImageData != nil,
                  entry.photoLocation == nil,
                  !didFetchInitialPhotoLocation else { return }
            didFetchInitialPhotoLocation = true
            await applyCurrentLocationToPhoto()
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPickerView { pickedPhoto in
                selectedImageData = pickedPhoto.data
                if allowsDateEditing, let date = pickedPhoto.date {
                    entry.date = date
                }
                Task {
                    await applyCurrentLocationToPhoto()
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isPhotoLibraryPresented) {
            PhotoLibraryPickerView { pickedPhoto in
                selectedImageData = pickedPhoto.data

                if allowsDateEditing, let date = pickedPhoto.date {
                    entry.date = date
                }

                if let location = pickedPhoto.location {
                    entry.photoLocation = location
                    Task {
                        if let name = await placeName(for: CLLocation(latitude: location.latitude, longitude: location.longitude)) {
                            entry.photoLocation?.name = name
                        }
                    }
                } else {
                    entry.photoLocation = nil
                }
            }
            .ignoresSafeArea()
        }
    }

    private var editorTitle: String {
        if let titleOverride {
            return titleOverride
        }

        return Calendar.current.isDateInToday(entry.date)
            ? "记录今天"
            : "补录 \(entry.date.formatted(.dateTime.month().day()))"
    }

    private var manualWeatherOptions: [(code: Int, title: String, symbol: String)] {
        [
            (0, "晴天", "sun.max.fill"),
            (2, "多云", "cloud.sun.fill"),
            (3, "阴天", "cloud.fill"),
            (45, "有雾", "cloud.fog.fill"),
            (61, "雨天", "cloud.rain.fill"),
            (71, "雪天", "cloud.snow.fill"),
            (95, "雷雨", "cloud.bolt.rain.fill")
        ]
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let selectedImageData, let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let url = store.imageURL(for: entry) {
            CachedPhotoView(
                url: url,
                targetSize: CGSize(width: 720, height: 560),
                contentMode: .fill
            ) {
                Color.secondary.opacity(0.12)
            }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func fetchWeather() {
        isFetchingWeather = true
        errorMessage = nil
        weatherStatus = "正在获取天气..."

        Task {
            do {
                let weather = try await WeatherService().currentWeather()
                entry.weather = weather
                weatherStatus = "\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C"
            } catch {
                do {
                    let weather = try await WeatherService().fallbackWeather()
                    entry.weather = weather
                    weatherStatus = "定位不可用，已使用上海天气：\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C"
                    errorMessage = "当前位置获取失败：\(error.localizedDescription)"
                } catch {
                    weatherStatus = "天气获取失败"
                    errorMessage = error.localizedDescription
                }
            }

            isFetchingWeather = false
        }
    }

    private func applyManualWeather(code: Int) {
        guard code >= 0 else { return }

        entry.weather = WeatherSnapshot(
            temperature: entry.weather?.temperature ?? 0,
            windSpeed: entry.weather?.windSpeed ?? 0,
            weatherCode: code,
            fetchedAt: Date()
        )

        if let weather = entry.weather {
            weatherStatus = "\(weather.summary) \(weather.temperature.formatted(.number.precision(.fractionLength(0))))°C"
        }
    }

    private func applyCurrentLocationToPhoto() async {
        do {
            let location = try await CurrentLocationProvider().currentLocation()
            var photoLocation = PhotoLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                name: nil
            )
            if let name = await placeName(for: location) {
                photoLocation.name = name
            }
            entry.photoLocation = photoLocation
        } catch {
            if entry.photoLocation == nil {
                errorMessage = "照片位置获取失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct PhotoSourceButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
            )
    }
}
