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

    private func weather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m,wind_speed_10m,weather_code&timezone=auto")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return WeatherSnapshot(
            temperature: decoded.current.temperature2m,
            windSpeed: decoded.current.windSpeed10m,
            weatherCode: decoded.current.weatherCode,
            fetchedAt: Date()
        )
    }
}

private struct OpenMeteoResponse: Decodable {
    var current: Current

    struct Current: Decodable {
        var temperature2m: Double
        var windSpeed10m: Double
        var weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case windSpeed10m = "wind_speed_10m"
            case weatherCode = "weather_code"
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
