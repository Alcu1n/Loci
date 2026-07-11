import CoreLocation
import Foundation
import MapKit

@MainActor
final class CoreLocationClient: NSObject, CurrentLocationClient, @preconcurrency CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func locate() async throws -> PlaceSuggestion {
        guard CLLocationManager.locationServicesEnabled() else { throw LociError.locationUnavailable }
        let location = try await requestOneLocation()
        return await reverseGeocode(location)
    }

    private func requestOneLocation() async throws -> CLLocation {
        guard continuation == nil else { throw LociError.locationUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(LociError.locationTimedOut))
            }
            switch manager.authorizationStatus {
            case .denied, .restricted:
                finish(with: .failure(LociError.locationDenied))
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            @unknown default:
                finish(with: .failure(LociError.locationUnavailable))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LociError.locationDenied))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(LociError.locationUnavailable))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private func reverseGeocode(_ location: CLLocation) async -> PlaceSuggestion {
        let fallback = PlaceSuggestion(name: "Current location", city: "CURRENT LOCATION", country: "", latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, zoom: 13)
        do {
            let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
            let city = placemark?.locality ?? placemark?.subLocality ?? "CURRENT LOCATION"
            let country = placemark?.country ?? placemark?.administrativeArea ?? ""
            let name = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
            return PlaceSuggestion(name: name, city: city, country: country, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, zoom: 13)
        } catch {
            return fallback
        }
    }
}
