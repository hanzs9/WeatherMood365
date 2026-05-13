import CoreLocation
import Foundation

enum WeatherError: LocalizedError {
    case locationUnavailable
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .locationUnavailable: "无法获取当前位置。请在系统设置中允许位置权限。"
        case .invalidResponse: "天气服务暂时没有返回可用数据。"
        case .timedOut: "定位等待超时。"
        }
    }
}

final class WeatherService {
    func currentWeather() async throws -> WeatherSnapshot {
        let location = try await CurrentLocationProvider().currentLocation()
        return try await weather(for: location.coordinate)
    }

    func fallbackWeather() async throws -> WeatherSnapshot {
        try await weather(for: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737))
    }

    func weather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        async let forecast = Self.fetchForecast(for: coordinate)
        async let airQuality = Self.fetchAirQuality(for: coordinate)

        let forecastResponse = try await forecast
        let airQualityResponse = try? await airQuality

        return WeatherSnapshot(
            temperature: forecastResponse.current.temperature2m,
            windSpeed: forecastResponse.current.windSpeed10m,
            weatherCode: forecastResponse.current.weatherCode,
            fetchedAt: Date(),
            visibility: forecastResponse.current.visibility,
            aqi: airQualityResponse?.current.aqi,
            aerosolOpticalDepth: airQualityResponse?.current.aerosolOpticalDepth
        )
    }

    private static func fetchForecast(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoForecastResponse {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m,wind_speed_10m,weather_code,visibility&timezone=auto")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }

        return try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
    }

    private static func fetchAirQuality(for coordinate: CLLocationCoordinate2D) async throws -> OpenMeteoAirQualityResponse {
        let url = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=european_aqi,aerosol_optical_depth&timezone=auto")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }

        return try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    var current: Current

    struct Current: Decodable {
        var temperature2m: Double
        var windSpeed10m: Double
        var weatherCode: Int
        var visibility: Double?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case windSpeed10m = "wind_speed_10m"
            case weatherCode = "weather_code"
            case visibility
        }
    }
}

private struct OpenMeteoAirQualityResponse: Decodable {
    var current: Current

    struct Current: Decodable {
        var aqi: Double?
        var aerosolOpticalDepth: Double?

        enum CodingKeys: String, CodingKey {
            case aqi = "european_aqi"
            case aerosolOpticalDepth = "aerosol_optical_depth"
        }
    }
}

@MainActor
final class CurrentLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        try await currentLocation().coordinate
    }

    func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(with: .failure(WeatherError.timedOut))
            }

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finish(with: .failure(WeatherError.locationUnavailable))
            @unknown default:
                finish(with: .failure(WeatherError.locationUnavailable))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            finish(with: .failure(WeatherError.locationUnavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(WeatherError.locationUnavailable))
            return
        }

        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let coordinate):
            continuation.resume(returning: coordinate)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
