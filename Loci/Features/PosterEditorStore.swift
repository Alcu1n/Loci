import Foundation
import Observation

@MainActor @Observable final class PosterEditorStore {
    enum Sheet: Identifiable { case location, style, text, settings; var id: String { String(describing: self) } }
    var document: PosterDocument
    var activeSheet: Sheet?
    var searchQuery = ""
    var suggestions: [PlaceSuggestion] = []
    var isSearching = false
    var errorMessage: String?
    var isExporting = false
    var isLocating = false
    var exportedURL: URL?
    var confirmationMessage: String?
    var previewViewport: MapViewport?
    private let drafts: any DraftRepository
    private let geocoder: any GeocodingClient
    private let offlineGeocoder: any OfflineGeocodingClient
    private let exporter: any ExportService
    private let currentLocation: any CurrentLocationClient
    private let photoLibrary: any PhotoLibrarySaver
    private var searchGeneration = 0
    private var viewportLookupGeneration = 0
    private var lastReverseCoordinate: (latitude: Double, longitude: Double)?
    private var lastDistrictLookupCoordinate: (latitude: Double, longitude: Double)?
    private var searchTask: Task<Void, Never>?
    private var viewportTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var pendingOfflineViewport: MapViewport?
    private var offlineGeneration = 0

    init(document: PosterDocument, drafts: any DraftRepository, geocoder: any GeocodingClient, offlineGeocoder: any OfflineGeocodingClient = EmptyOfflineGeocodingClient(), exporter: any ExportService, currentLocation: any CurrentLocationClient, photoLibrary: any PhotoLibrarySaver) { self.document = document; self.drafts = drafts; self.geocoder = geocoder; self.offlineGeocoder = offlineGeocoder; self.exporter = exporter; self.currentLocation = currentLocation; self.photoLibrary = photoLibrary }

    static func live() -> PosterEditorStore {
        let drafts = UserDefaultsDraftRepository(); let renderer = MapLibreRenderer(); let compositor = CoreGraphicsCompositor()
        let document = (try? drafts.load()) ?? .tokyo
        let offlineGeocoder: any OfflineGeocodingClient = (try? OfflineGazetteer.live()) ?? EmptyOfflineGeocodingClient()
        let store = PosterEditorStore(document: document, drafts: drafts, geocoder: NominatimGeocodingClient(), offlineGeocoder: offlineGeocoder, exporter: LocalExportService(renderer: renderer, compositor: compositor), currentLocation: CoreLocationClient(), photoLibrary: SystemPhotoLibrarySaver())
        Task { try? await offlineGeocoder.preload() }
        return store
    }

    func save() { document.updatedAt = .now; do { try drafts.save(document) } catch { errorMessage = error.localizedDescription } }
    func newPoster() { invalidateLocationLookups(); document = .tokyo; previewViewport = nil; lastReverseCoordinate = nil; lastDistrictLookupCoordinate = nil; save() }
    func selectTheme(_ theme: PosterTheme) { document.themeID = theme.id; save() }
    func setLayout(_ layout: PosterLayout) { document.layout = layout; previewViewport = nil; save() }
    func toggleLayer(_ keyPath: WritableKeyPath<LayerVisibility, Bool>) { document.layerVisibility[keyPath: keyPath].toggle(); save() }
    func updateCity(_ city: String) { document.location.city = city.uppercased(); document.title = city.uppercased(); document.typography.cityIsUserEdited = true; save() }
    func updateCountry(_ country: String) { document.location.country = country.uppercased(); document.typography.countryIsUserEdited = true; save() }
    func select(_ suggestion: PlaceSuggestion) {
        invalidateLocationLookups()
        document.typography.cityIsUserEdited = false
        document.typography.countryIsUserEdited = false
        applyResolvedLocation(suggestion)
        document.camera = .init(latitude: suggestion.latitude, longitude: suggestion.longitude, zoom: suggestion.zoom)
        previewViewport = nil
        lastReverseCoordinate = (suggestion.latitude, suggestion.longitude)
        lastDistrictLookupCoordinate = suggestion.district.isEmpty ? nil : (suggestion.latitude, suggestion.longitude)
        save()
        activeSheet = nil
    }
    func updateViewport(_ viewport: MapViewport) {
        guard viewport.isValid else { return }
        previewViewport = viewport
        guard document.camera != viewport.camera else { return }
        viewportTask?.cancel()
        viewportLookupGeneration += 1
        document.camera = viewport.camera
        scheduleOfflineLookup(viewport)
    }
    func applyCoordinates(latitude: String, longitude: String) {
        guard let latitude = Double(latitude), let longitude = Double(longitude), (-90...90).contains(latitude), (-180...180).contains(longitude) else { errorMessage = LociError.invalidCoordinates.localizedDescription; return }
        invalidateLocationLookups()
        let viewportSize = previewViewport?.size ?? .init(width: 2, height: 2)
        document.location.latitude = latitude
        document.location.longitude = longitude
        document.camera.latitude = latitude
        document.camera.longitude = longitude
        previewViewport = nil
        lastReverseCoordinate = nil
        lastDistrictLookupCoordinate = nil
        settleViewport(.init(camera: document.camera, size: viewportSize))
        activeSheet = nil
    }
    func startSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { suggestions = []; return }
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            let results = try await geocoder.search(query: query)
            guard generation == searchGeneration, query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            suggestions = results
            if results.isEmpty { errorMessage = LociError.noResults.localizedDescription }
        } catch is CancellationError {
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func settleViewport(_ viewport: MapViewport) {
        guard viewport.isValid else { return }
        save()
        let needsDistrictLookup = viewport.camera.zoom >= 13 && document.location.district == nil && !document.typography.cityIsUserEdited && !isNearLastDistrictLookup(viewport.camera)
        if let previous = lastReverseCoordinate,
           abs(previous.latitude - viewport.camera.latitude) < 0.002,
           abs(previous.longitude - viewport.camera.longitude) < 0.002,
           !needsDistrictLookup { return }
        viewportTask?.cancel()
        viewportTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await viewportDidSettle(viewport)
        }
    }

    func viewportDidSettle(_ viewport: MapViewport) async {
        guard viewport.isValid else { return }
        let coordinate = (viewport.camera.latitude, viewport.camera.longitude)
        let needsDistrictLookup = viewport.camera.zoom >= 13 && document.location.district == nil && !document.typography.cityIsUserEdited && !isNearLastDistrictLookup(viewport.camera)
        if let previous = lastReverseCoordinate,
           abs(previous.latitude - coordinate.0) < 0.002,
           abs(previous.longitude - coordinate.1) < 0.002,
           !needsDistrictLookup { return }
        viewportLookupGeneration += 1
        let generation = viewportLookupGeneration
        lastReverseCoordinate = (coordinate.0, coordinate.1)
        if needsDistrictLookup { lastDistrictLookupCoordinate = (coordinate.0, coordinate.1) }
        do {
            let resolved = try await geocoder.reverseGeocode(latitude: coordinate.0, longitude: coordinate.1)
            guard generation == viewportLookupGeneration,
                  abs(document.camera.latitude - coordinate.0) < 0.002,
                  abs(document.camera.longitude - coordinate.1) < 0.002 else { return }
            document.location.latitude = coordinate.0
            document.location.longitude = coordinate.1
            applyResolvedLocation(resolved, updateCoordinates: false)
            lastDistrictLookupCoordinate = (coordinate.0, coordinate.1)
            save()
        } catch is CancellationError {
        } catch {
            if generation == viewportLookupGeneration {
                lastReverseCoordinate = nil
                if needsDistrictLookup { lastDistrictLookupCoordinate = nil }
                if abs(document.camera.latitude - coordinate.0) < 0.002,
                   abs(document.camera.longitude - coordinate.1) < 0.002 { save() }
            }
        }
    }

    private func isNearLastDistrictLookup(_ camera: PosterCamera) -> Bool {
        guard let previous = lastDistrictLookupCoordinate else { return false }
        return abs(previous.latitude - camera.latitude) < 0.002 && abs(previous.longitude - camera.longitude) < 0.002
    }

    private func invalidateLocationLookups() {
        viewportTask?.cancel()
        viewportTask = nil
        viewportLookupGeneration += 1
        pendingOfflineViewport = nil
        offlineGeneration += 1
    }

    private func scheduleOfflineLookup(_ viewport: MapViewport) {
        offlineGeneration += 1
        pendingOfflineViewport = viewport
        guard offlineTask == nil else { return }
        offlineTask = Task { await drainOfflineLookups() }
    }

    private func drainOfflineLookups() async {
        while let viewport = pendingOfflineViewport {
            pendingOfflineViewport = nil
            let generation = offlineGeneration
            do {
                let resolved = try await offlineGeocoder.resolve(latitude: viewport.camera.latitude, longitude: viewport.camera.longitude, zoom: viewport.camera.zoom)
                if generation == offlineGeneration,
                   abs(document.camera.latitude - viewport.camera.latitude) < 0.002,
                   abs(document.camera.longitude - viewport.camera.longitude) < 0.002 {
                    document.location.latitude = viewport.camera.latitude
                    document.location.longitude = viewport.camera.longitude
                    if let resolved { applyResolvedLocation(resolved, updateCoordinates: false) }
                    else { clearAutomaticLocation() }
                }
            } catch {
                // Online reverse geocoding remains the precision fallback.
            }
            if pendingOfflineViewport != nil { try? await Task.sleep(for: .milliseconds(80)) }
        }
        offlineTask = nil
    }

    private func clearAutomaticLocation() {
        document.location.resolvedName = nil
        document.location.district = nil
        document.location.administrativeArea = nil
        if !document.typography.cityIsUserEdited { document.location.city = nil }
        if !document.typography.countryIsUserEdited {
            document.location.country = nil
            document.location.countryCode = nil
            document.location.continent = nil
        }
    }

    private func applyResolvedLocation(_ suggestion: PlaceSuggestion, updateCoordinates: Bool = true) {
        if updateCoordinates {
            document.location.latitude = suggestion.latitude
            document.location.longitude = suggestion.longitude
        }
        document.location.resolvedName = suggestion.name
        document.location.district = suggestion.district.uppercased().nilIfEmpty
        document.location.administrativeArea = suggestion.administrativeArea.uppercased().nilIfEmpty
        document.location.countryCode = suggestion.countryCode.uppercased().nilIfEmpty
        document.location.continent = suggestion.continent.uppercased().nilIfEmpty
        if !document.typography.cityIsUserEdited {
            let city = suggestion.city.uppercased().nilIfEmpty ?? suggestion.administrativeArea.uppercased().nilIfEmpty ?? suggestion.district.uppercased().nilIfEmpty
            document.location.city = city
            document.title = city ?? document.title
        }
        if !document.typography.countryIsUserEdited {
            document.location.country = suggestion.country.uppercased().nilIfEmpty
        }
    }
    func useCurrentLocation() async { guard !isLocating else { return }; isLocating = true; defer { isLocating = false }; do { select(try await currentLocation.locate()) } catch { errorMessage = error.localizedDescription } }
    func export() async { guard let previewViewport else { errorMessage = LociError.previewUnavailable.localizedDescription; return }; isExporting = true; defer { isExporting = false }; do { exportedURL = try await exporter.export(document: document, viewport: previewViewport) } catch { errorMessage = error.localizedDescription } }
    func exportToPhotos() async { guard let previewViewport else { errorMessage = LociError.previewUnavailable.localizedDescription; return }; isExporting = true; defer { isExporting = false }; do { let url = try await exporter.export(document: document, viewport: previewViewport); exportedURL = url; try await photoLibrary.saveImage(at: url); confirmationMessage = "Poster saved to Photos." } catch { errorMessage = error.localizedDescription } }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
