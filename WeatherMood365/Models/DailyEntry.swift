import CoreLocation
import Foundation

struct DailyEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var mood: Mood
    var note: String
    var photoFilename: String?
    var weather: WeatherSnapshot?
    var photoLocation: PhotoLocation?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mood: Mood = .plain,
        note: String = "",
        photoFilename: String? = nil,
        weather: WeatherSnapshot? = nil,
        photoLocation: PhotoLocation? = nil
    ) {
        self.id = id
        self.date = date
        self.mood = mood
        self.note = note
        self.photoFilename = photoFilename
        self.weather = weather
        self.photoLocation = photoLocation
    }
}

enum Mood: String, CaseIterable, Codable, Identifiable {
    case happy
    case plain
    case cozy
    case irritated
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .happy: "开心"
        case .plain: "平淡"
        case .cozy: "惬意"
        case .irritated: "烦躁"
        case .low: "低落"
        }
    }

    var symbol: String {
        switch self {
        case .happy: "face.smiling.fill"
        case .plain: "circle.lefthalf.filled"
        case .cozy: "leaf.circle.fill"
        case .irritated: "bolt.circle.fill"
        case .low: "cloud.rain.circle.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "happy":
            self = .happy
        case "plain", "calm", "cloudy":
            self = .plain
        case "cozy":
            self = .cozy
        case "irritated", "hard":
            self = .irritated
        case "low", "tired":
            self = .low
        default:
            self = .plain
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct PhotoLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String?

    var displayText: String {
        if let name, !name.isEmpty {
            return name
        }

        return String(format: "%.4f, %.4f", latitude, longitude)
    }
}

func placeName(for location: CLLocation) async -> String? {
    let cacheKey = String(format: "%.4f,%.4f", location.coordinate.latitude, location.coordinate.longitude)
    if let cached = await PlaceNameMemoryCache.shared.name(for: cacheKey) {
        return cached
    }

    return await withCheckedContinuation { continuation in
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let placemark = placemarks?.first
            let parts = [
                placemark?.locality ?? placemark?.administrativeArea,
                placemark?.subLocality
            ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            let name = parts.isEmpty ? nil : parts.joined(separator: " · ")
            if let name {
                Task {
                    await PlaceNameMemoryCache.shared.setName(name, for: cacheKey)
                }
            }
            continuation.resume(returning: name)
        }
    }
}

private actor PlaceNameMemoryCache {
    static let shared = PlaceNameMemoryCache()

    private var cache: [String: String] = [:]

    func name(for key: String) -> String? {
        cache[key]
    }

    func setName(_ name: String, for key: String) {
        guard cache.count < 300 || cache[key] != nil else { return }
        cache[key] = name
    }
}

struct WeatherSnapshot: Codable, Equatable {
    var temperature: Double
    var windSpeed: Double
    var weatherCode: Int
    var fetchedAt: Date

    var summary: String {
        switch weatherCode {
        case 0: "晴朗"
        case 1, 2, 3: "多云"
        case 45, 48: "有雾"
        case 51, 53, 55, 56, 57: "毛毛雨"
        case 61, 63, 65, 66, 67: "下雨"
        case 71, 73, 75, 77: "下雪"
        case 80, 81, 82: "阵雨"
        case 95, 96, 99: "雷雨"
        default: "未知天气"
        }
    }

    var symbol: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2, 3: "cloud.sun.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}
