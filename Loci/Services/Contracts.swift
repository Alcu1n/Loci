import Foundation
import UIKit

protocol MapRenderer: Sendable { func snapshot(document: PosterDocument, size: CGSize, viewport: MapViewport) async throws -> UIImage }
protocol GeocodingClient: Sendable {
    func search(query: String) async throws -> [PlaceSuggestion]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion
}
protocol OfflineGeocodingClient: Sendable {
    func preload() async throws
    func resolve(latitude: Double, longitude: Double, zoom: Double) async throws -> PlaceSuggestion?
}
struct EmptyOfflineGeocodingClient: OfflineGeocodingClient {
    func preload() async throws {}
    func resolve(latitude: Double, longitude: Double, zoom: Double) async throws -> PlaceSuggestion? { nil }
}
protocol CurrentLocationClient: Sendable { func locate() async throws -> PlaceSuggestion }
protocol DraftRepository: Sendable { func load() throws -> PosterDocument?; func save(_ document: PosterDocument) throws }
protocol PosterCompositor: Sendable { func render(map: UIImage, document: PosterDocument, output: CGSize) throws -> UIImage }
protocol ExportService: Sendable { func export(document: PosterDocument, viewport: MapViewport) async throws -> URL }
protocol PhotoLibrarySaver: Sendable { func saveImage(at url: URL) async throws }

struct MapViewport: Equatable, Sendable {
    let camera: PosterCamera
    let size: CGSize

    var isValid: Bool { size.width > 1 && size.height > 1 }

    func outputScale(for output: CGSize) -> CGFloat {
        guard isValid, output.width > 0, output.height > 0 else { return 0 }
        return min(output.width / size.width, output.height / size.height)
    }
}

enum PosterFade {
    static let topFraction: CGFloat = 0.22
    static let bottomFraction: CGFloat = 0.63
    static let opacity: CGFloat = 0.96
}

enum PosterTypographyLayout {
    static let contentBottomFraction: CGFloat = 0.035
    static let cityYFraction: CGFloat = 0.69
    static let countryYFraction: CGFloat = 0.79
    static let separatorYFraction: CGFloat = 0.835
    static let separatorWidthFraction: CGFloat = 0.24
    static let subtitleYFraction: CGFloat = 0.86
    static let coordinatesYFraction: CGFloat = 0.90
    static let footerYFraction: CGFloat = 0.965
}

struct PlaceSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let district: String
    let city: String
    let administrativeArea: String
    let country: String
    let countryCode: String
    let continent: String
    let isAdministrative: Bool
    let latitude: Double
    let longitude: Double
    let zoom: Double

    init(id: String = UUID().uuidString, name: String, district: String = "", city: String, administrativeArea: String = "", country: String, countryCode: String = "", continent: String = "", isAdministrative: Bool = true, latitude: Double, longitude: Double, zoom: Double) {
        self.id = id
        self.name = name
        self.district = district
        self.city = city
        self.administrativeArea = administrativeArea
        self.country = country
        self.countryCode = countryCode
        self.continent = continent
        self.isAdministrative = isAdministrative
        self.latitude = latitude
        self.longitude = longitude
        self.zoom = zoom
    }
}
enum LociError: LocalizedError { case unavailableConfiguration, invalidCoordinates, outputTooLarge, noResults, renderFailed, previewUnavailable, locationDenied, locationUnavailable, locationTimedOut, photoAccessDenied, photoSaveFailed
    var errorDescription: String? { switch self { case .unavailableConfiguration: "Map and search services need to be configured before this feature can connect."; case .invalidCoordinates: "Enter latitude from −90 to 90 and longitude from −180 to 180."; case .outputTooLarge: "This size exceeds Loci’s 12 MP export budget."; case .noResults: "No places found."; case .renderFailed: "Loci could not render this poster."; case .previewUnavailable: "Wait for the map preview to finish loading before exporting."; case .locationDenied: "Location access is off. Enable it for Loci in Settings to use your current place."; case .locationUnavailable: "Loci could not determine your current location."; case .locationTimedOut: "Location took too long. Check your signal and try again."; case .photoAccessDenied: "Photo access is off. Allow Loci to add photos in Settings."; case .photoSaveFailed: "Loci could not save this poster to Photos." } }
}
