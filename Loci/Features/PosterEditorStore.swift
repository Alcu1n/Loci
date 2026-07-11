import Foundation
import Observation

@MainActor @Observable final class PosterEditorStore {
    enum Sheet: Identifiable { case location, style, text, settings; var id: String { String(describing: self) } }
    var document: PosterDocument
    var activeSheet: Sheet?
    var searchQuery = ""
    var suggestions: [PlaceSuggestion] = []
    var errorMessage: String?
    var isExporting = false
    var isLocating = false
    var exportedURL: URL?
    var confirmationMessage: String?
    var previewViewport: MapViewport?
    private let drafts: any DraftRepository
    private let geocoder: any GeocodingClient
    private let exporter: any ExportService
    private let currentLocation: any CurrentLocationClient
    private let photoLibrary: any PhotoLibrarySaver

    init(document: PosterDocument, drafts: any DraftRepository, geocoder: any GeocodingClient, exporter: any ExportService, currentLocation: any CurrentLocationClient, photoLibrary: any PhotoLibrarySaver) { self.document = document; self.drafts = drafts; self.geocoder = geocoder; self.exporter = exporter; self.currentLocation = currentLocation; self.photoLibrary = photoLibrary }

    static func live() -> PosterEditorStore {
        let drafts = UserDefaultsDraftRepository(); let renderer = MapLibreRenderer(); let compositor = CoreGraphicsCompositor()
        let document = (try? drafts.load()) ?? .tokyo
        return PosterEditorStore(document: document, drafts: drafts, geocoder: ApplePlaceSearchClient(), exporter: LocalExportService(renderer: renderer, compositor: compositor), currentLocation: CoreLocationClient(), photoLibrary: SystemPhotoLibrarySaver())
    }

    func save() { document.updatedAt = .now; do { try drafts.save(document) } catch { errorMessage = error.localizedDescription } }
    func newPoster() { document = .tokyo; previewViewport = nil; save() }
    func selectTheme(_ theme: PosterTheme) { document.themeID = theme.id; save() }
    func setLayout(_ layout: PosterLayout) { document.layout = layout; previewViewport = nil; save() }
    func toggleLayer(_ keyPath: WritableKeyPath<LayerVisibility, Bool>) { document.layerVisibility[keyPath: keyPath].toggle(); save() }
    func updateCity(_ city: String) { document.location.city = city.uppercased(); document.title = city.uppercased(); document.typography.cityIsUserEdited = true; save() }
    func updateCountry(_ country: String) { document.location.country = country.uppercased(); document.typography.countryIsUserEdited = true; save() }
    func select(_ suggestion: PlaceSuggestion) { document.location = .init(latitude: suggestion.latitude, longitude: suggestion.longitude, resolvedName: suggestion.name, city: suggestion.city.uppercased(), country: suggestion.country.uppercased()); document.camera = .init(latitude: suggestion.latitude, longitude: suggestion.longitude, zoom: suggestion.zoom); previewViewport = nil; if !document.typography.cityIsUserEdited { document.title = suggestion.city.uppercased() }; save(); activeSheet = nil }
    func updateViewport(_ viewport: MapViewport) { guard viewport.isValid else { return }; previewViewport = viewport; guard document.camera != viewport.camera else { return }; document.camera = viewport.camera; save() }
    func applyCoordinates(latitude: String, longitude: String) { guard let latitude = Double(latitude), let longitude = Double(longitude), (-90...90).contains(latitude), (-180...180).contains(longitude) else { errorMessage = LociError.invalidCoordinates.localizedDescription; return }; document.location.latitude = latitude; document.location.longitude = longitude; document.camera.latitude = latitude; document.camera.longitude = longitude; previewViewport = nil; save(); activeSheet = nil }
    func search() async { guard searchQuery.count >= 2 else { suggestions = []; return }; do { suggestions = try await geocoder.search(query: searchQuery); if suggestions.isEmpty { errorMessage = LociError.noResults.localizedDescription } } catch { errorMessage = error.localizedDescription } }
    func useCurrentLocation() async { guard !isLocating else { return }; isLocating = true; defer { isLocating = false }; do { select(try await currentLocation.locate()) } catch { errorMessage = error.localizedDescription } }
    func export() async { guard let previewViewport else { errorMessage = LociError.previewUnavailable.localizedDescription; return }; isExporting = true; defer { isExporting = false }; do { exportedURL = try await exporter.export(document: document, viewport: previewViewport) } catch { errorMessage = error.localizedDescription } }
    func exportToPhotos() async { guard let previewViewport else { errorMessage = LociError.previewUnavailable.localizedDescription; return }; isExporting = true; defer { isExporting = false }; do { let url = try await exporter.export(document: document, viewport: previewViewport); exportedURL = url; try await photoLibrary.saveImage(at: url); confirmationMessage = "Poster saved to Photos." } catch { errorMessage = error.localizedDescription } }
}
