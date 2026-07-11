import Foundation
import UIKit

protocol MapRenderer: Sendable { func snapshot(document: PosterDocument, size: CGSize, viewport: MapViewport) async throws -> UIImage }
protocol GeocodingClient: Sendable { func search(query: String) async throws -> [PlaceSuggestion] }
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

struct PlaceSuggestion: Identifiable, Equatable, Sendable { let id = UUID(); let name: String; let city: String; let country: String; let latitude: Double; let longitude: Double; let zoom: Double }
enum LociError: LocalizedError { case unavailableConfiguration, invalidCoordinates, outputTooLarge, noResults, renderFailed, previewUnavailable, locationDenied, locationUnavailable, locationTimedOut, photoAccessDenied, photoSaveFailed
    var errorDescription: String? { switch self { case .unavailableConfiguration: "Map and search services need to be configured before this feature can connect."; case .invalidCoordinates: "Enter latitude from −90 to 90 and longitude from −180 to 180."; case .outputTooLarge: "This size exceeds Loci’s 12 MP export budget."; case .noResults: "No places found."; case .renderFailed: "Loci could not render this poster."; case .previewUnavailable: "Wait for the map preview to finish loading before exporting."; case .locationDenied: "Location access is off. Enable it for Loci in Settings to use your current place."; case .locationUnavailable: "Loci could not determine your current location."; case .locationTimedOut: "Location took too long. Check your signal and try again."; case .photoAccessDenied: "Photo access is off. Allow Loci to add photos in Settings."; case .photoSaveFailed: "Loci could not save this poster to Photos." } }
}
