import XCTest
@testable import Loci

final class LociTests: XCTestCase {
    func testOfflineGazetteerResolvesCountriesImmediatelyAcrossContinents() async throws {
        let resolver = try makeOfflineGazetteer()

        let china = try await resolver.resolve(latitude: 30.5728, longitude: 104.0668, zoom: 6)
        let japan = try await resolver.resolve(latitude: 35.6762, longitude: 139.6503, zoom: 6)
        let unitedStates = try await resolver.resolve(latitude: 40.7128, longitude: -74.0060, zoom: 6)
        let ocean = try await resolver.resolve(latitude: 0, longitude: -140, zoom: 6)

        XCTAssertEqual(china?.countryCode, "CN")
        XCTAssertEqual(china?.country, "China")
        XCTAssertEqual(japan?.countryCode, "JP")
        XCTAssertEqual(japan?.country, "Japan")
        XCTAssertEqual(unitedStates?.countryCode, "US")
        XCTAssertNil(ocean)
    }

    func testOfflineResourcesStayWithinAppSizeBudget() throws {
        let resources = offlineResourceDirectory()
        let countries = try FileManager.default.attributesOfItem(atPath: resources.appending(path: "countries.json").path)[.size] as? NSNumber
        let cities = try FileManager.default.attributesOfItem(atPath: resources.appending(path: "cities.sqlite").path)[.size] as? NSNumber

        XCTAssertLessThanOrEqual(countries?.intValue ?? .max, 3 * 1_024 * 1_024)
        XCTAssertLessThanOrEqual(cities?.intValue ?? .max, 15 * 1_024 * 1_024)
    }

    func testOfflineGazetteerResolvesNearestCityAndAdministrativeArea() async throws {
        let resolver = try makeOfflineGazetteer()

        let tokyo = try await resolver.resolve(latitude: 35.6762, longitude: 139.6503, zoom: 11)
        let paris = try await resolver.resolve(latitude: 48.8566, longitude: 2.3522, zoom: 11)

        XCTAssertEqual(tokyo?.city, "Tokyo")
        XCTAssertEqual(tokyo?.countryCode, "JP")
        XCTAssertEqual(paris?.city, "Paris")
        XCTAssertEqual(paris?.countryCode, "FR")
    }

    func testLocationPresentationNeverRepeatsEquivalentLabels() {
        var document = PosterDocument.tokyo
        document.location.country = "CHINA"
        document.location.continent = "China"
        document.camera.zoom = 6

        XCTAssertEqual(document.locationPresentation, .init(primary: "CHINA", secondary: ""))
    }

    @MainActor
    func testMapMovementAppliesOfflineCountryBeforeOnlineReverseGeocoding() async {
        let japan = PlaceSuggestion(name: "Japan", city: "", country: "Japan", countryCode: "JP", continent: "Asia", latitude: 35.6762, longitude: 139.6503, zoom: 6)
        let store = makeStore(document: .tokyo, geocoder: StubGeocoder(reverseResult: nil), offlineGeocoder: StubOfflineGeocoder(result: japan))
        let viewport = MapViewport(camera: .init(latitude: 35.6762, longitude: 139.6503, zoom: 6), size: .init(width: 300, height: 400))

        store.updateViewport(viewport)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.document.location.country, "JAPAN")
        XCTAssertEqual(store.document.locationPresentation, .init(primary: "JAPAN", secondary: "ASIA"))
    }

    @MainActor
    func testMapMovementPreventsLateOnlineResultFromOverwritingOfflineLabel() async {
        let japan = PlaceSuggestion(name: "Japan", city: "", country: "Japan", countryCode: "JP", continent: "Asia", latitude: 35.6762, longitude: 139.6503, zoom: 6)
        let store = makeStore(document: .tokyo, geocoder: DelayedGeocoder(), offlineGeocoder: StubOfflineGeocoder(result: japan))
        let oldViewport = MapViewport(camera: .init(latitude: 35, longitude: 139, zoom: 11), size: .init(width: 300, height: 400))
        let japanViewport = MapViewport(camera: .init(latitude: 35.6762, longitude: 139.6503, zoom: 6), size: .init(width: 300, height: 400))

        let oldLookup = Task { await store.viewportDidSettle(oldViewport) }
        try? await Task.sleep(for: .milliseconds(10))
        store.updateViewport(japanViewport)
        await oldLookup.value

        XCTAssertEqual(store.document.location.country, "JAPAN")
        XCTAssertEqual(store.document.locationPresentation.primary, "JAPAN")
    }

    func testNominatimRanksAdministrativeExactMatchBeforeBusinessContainsMatch() throws {
        let payload = Data("""
        [
          {"place_id":1,"lat":"39.90","lon":"116.40","name":"Tokyo Matcha Shop","display_name":"Tokyo Matcha Shop, Beijing, China","category":"shop","type":"tea","address":{"shop":"Tokyo Matcha Shop","city":"Beijing","country":"China","country_code":"cn"}},
          {"place_id":2,"lat":"35.68","lon":"139.69","name":"Tokyo","display_name":"Tokyo, Japan","category":"boundary","type":"administrative","address":{"city":"Tokyo","country":"Japan","country_code":"jp"}}
        ]
        """.utf8)

        let results = try NominatimResponseParser.parseSearch(data: payload, query: "tokyo")

        XCTAssertEqual(results.map(\.name), ["Tokyo, Japan", "Tokyo Matcha Shop, Beijing, China"])
        XCTAssertEqual(results.first?.city, "Tokyo")
        XCTAssertEqual(results.first?.countryCode, "JP")
    }

    func testNominatimSearchKeepsDistinctAdministrativeNamesAndDeduplicatesSamePlace() throws {
        let payload = Data("""
        [
          {"place_id":1,"lat":"35.69","lon":"139.75","name":"Chiyoda","display_name":"Chiyoda, Tokyo, Japan","category":"boundary","type":"administrative","address":{"city_district":"Chiyoda","city":"Tokyo","country":"Japan","country_code":"jp"}},
          {"place_id":2,"lat":"36.22","lon":"139.44","name":"Chiyoda","display_name":"Chiyoda, Gunma, Japan","category":"boundary","type":"administrative","address":{"town":"Chiyoda","state":"Gunma","country":"Japan","country_code":"jp"}},
          {"place_id":3,"lat":"35.69001","lon":"139.75001","name":"Chiyoda","display_name":"Chiyoda, Tokyo, Japan","category":"place","type":"suburb","address":{"city_district":"Chiyoda","city":"Tokyo","country":"Japan","country_code":"jp"}}
        ]
        """.utf8)

        let results = try NominatimResponseParser.parseSearch(data: payload, query: "chiyoda")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.name), ["Chiyoda, Tokyo, Japan", "Chiyoda, Gunma, Japan"])
    }

    func testNominatimNormalizationSupportsDiacriticsAndNonLatinNames() {
        XCTAssertEqual(NominatimResponseParser.normalized("São-Paulo"), "sao paulo")
        XCTAssertEqual(NominatimResponseParser.normalized("東京都"), "東京都")
    }

    func testNominatimParserHandlesEmptyMissingAndInvalidEntries() throws {
        XCTAssertEqual(try NominatimResponseParser.parseSearch(data: Data("[]".utf8), query: "nowhere"), [])
        let payload = Data("""
        [
          {"place_id":1,"lat":"999","lon":"2","name":"Invalid","display_name":"Invalid","category":"place","type":"city","address":{}},
          {"place_id":2,"lat":"1","lon":"2","name":"Region","display_name":"Region, Country","category":"boundary","type":"administrative","address":{"state":"Region","country":"Country","country_code":"zz"}}
        ]
        """.utf8)

        let results = try NominatimResponseParser.parseSearch(data: payload, query: "region")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.city, "")
        XCTAssertEqual(results.first?.administrativeArea, "Region")
    }

    func testLocationPresentationFollowsDistrictCityCountryAndEarthZoomLevels() {
        var document = PosterDocument.tokyo
        document.location = .init(latitude: 35.69, longitude: 139.75, resolvedName: "Chiyoda, Tokyo, Japan", district: "CHIYODA", city: "TOKYO", administrativeArea: "TOKYO", country: "JAPAN", countryCode: "JP", continent: "ASIA")

        document.camera.zoom = 13
        XCTAssertEqual(document.locationPresentation, .init(primary: "CHIYODA", secondary: "TOKYO"))
        document.camera.zoom = 10
        XCTAssertEqual(document.locationPresentation, .init(primary: "TOKYO", secondary: "JAPAN"))
        document.camera.zoom = 6
        XCTAssertEqual(document.locationPresentation, .init(primary: "JAPAN", secondary: "ASIA"))
        document.camera.zoom = 5.99
        XCTAssertEqual(document.locationPresentation, .init(primary: "EARTH", secondary: ""))
    }

    func testLocationPresentationPreservesManualTextAtLocalZooms() {
        var document = PosterDocument.tokyo
        document.location.district = "CHIYODA"
        document.location.city = "MY CITY"
        document.location.country = "MY COUNTRY"
        document.typography.cityIsUserEdited = true
        document.typography.countryIsUserEdited = true
        document.camera.zoom = 15

        XCTAssertEqual(document.locationPresentation, .init(primary: "MY CITY", secondary: "MY COUNTRY"))
    }

    func testNominatimClientCachesRepeatedSearches() async throws {
        let payload = Data("""
        [{"place_id":2,"lat":"35.68","lon":"139.69","name":"Tokyo","display_name":"Tokyo, Japan","category":"boundary","type":"administrative","address":{"city":"Tokyo","country":"Japan","country_code":"jp"}}]
        """.utf8)
        MockURLProtocol.reset(responseData: payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = NominatimGeocodingClient(endpoint: URL(string: "https://example.test")!, session: URLSession(configuration: configuration), minimumRequestInterval: .zero)

        _ = try await client.search(query: "Tokyo")
        _ = try await client.search(query: " tokyo ")

        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept-Language"), "en")
    }

    func testNominatimClientCachesRepeatedReverseLookups() async throws {
        let payload = Data("""
        {"place_id":2,"lat":"35.68","lon":"139.69","name":"Tokyo","display_name":"Tokyo, Japan","category":"boundary","type":"administrative","address":{"city":"Tokyo","country":"Japan","country_code":"jp"}}
        """.utf8)
        MockURLProtocol.reset(responseData: payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = NominatimGeocodingClient(endpoint: URL(string: "https://example.test")!, session: URLSession(configuration: configuration), minimumRequestInterval: .zero)

        _ = try await client.reverseGeocode(latitude: 35.68, longitude: 139.69)
        _ = try await client.reverseGeocode(latitude: 35.68001, longitude: 139.69001)

        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testNominatimClientSurfacesHTTPAndTimeoutFailures() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.reset(responseData: Data(), statusCode: 503)
        let httpClient = NominatimGeocodingClient(endpoint: URL(string: "https://example.test")!, session: URLSession(configuration: configuration), minimumRequestInterval: .zero)
        await XCTAssertThrowsErrorAsync { try await httpClient.search(query: "Tokyo") }

        MockURLProtocol.reset(responseData: Data(), error: URLError(.timedOut))
        let timeoutClient = NominatimGeocodingClient(endpoint: URL(string: "https://example.test")!, session: URLSession(configuration: configuration), minimumRequestInterval: .zero)
        await XCTAssertThrowsErrorAsync { try await timeoutClient.search(query: "Paris") }
    }

    @MainActor
    func testViewportReverseGeocodeUpdatesCoordinatesButPreservesManualText() async {
        var document = PosterDocument.tokyo
        document.location.city = "CUSTOM CITY"
        document.location.country = "CUSTOM COUNTRY"
        document.typography.cityIsUserEdited = true
        document.typography.countryIsUserEdited = true
        let resolved = PlaceSuggestion(name: "Shinjuku, Tokyo, Japan", district: "Shinjuku", city: "Tokyo", administrativeArea: "Tokyo", country: "Japan", countryCode: "JP", continent: "Asia", latitude: 35.7, longitude: 139.7, zoom: 13)
        let store = makeStore(document: document, geocoder: StubGeocoder(reverseResult: resolved))
        let viewport = MapViewport(camera: .init(latitude: 35.701, longitude: 139.701, zoom: 14), size: .init(width: 300, height: 400))

        await store.viewportDidSettle(viewport)

        XCTAssertEqual(store.document.location.latitude, 35.701)
        XCTAssertEqual(store.document.location.longitude, 139.701)
        XCTAssertEqual(store.document.location.district, "SHINJUKU")
        XCTAssertEqual(store.document.location.city, "CUSTOM CITY")
        XCTAssertEqual(store.document.location.country, "CUSTOM COUNTRY")
    }

    @MainActor
    func testSelectingSearchResultRestoresAutomaticLocationText() {
        var document = PosterDocument.tokyo
        document.typography.cityIsUserEdited = true
        document.typography.countryIsUserEdited = true
        let store = makeStore(document: document, geocoder: StubGeocoder(reverseResult: nil))
        let result = PlaceSuggestion(name: "Paris, France", city: "Paris", country: "France", countryCode: "FR", continent: "Europe", latitude: 48.8566, longitude: 2.3522, zoom: 11)

        store.select(result)

        XCTAssertFalse(store.document.typography.cityIsUserEdited)
        XCTAssertFalse(store.document.typography.countryIsUserEdited)
        XCTAssertEqual(store.document.location.city, "PARIS")
        XCTAssertEqual(store.document.location.country, "FRANCE")
    }

    @MainActor
    func testOlderReverseGeocodeResponseCannotOverwriteNewerMapCenter() async {
        let store = makeStore(document: .tokyo, geocoder: DelayedGeocoder())
        let oldViewport = MapViewport(camera: .init(latitude: 35.0, longitude: 139.0, zoom: 11), size: .init(width: 300, height: 400))
        let newViewport = MapViewport(camera: .init(latitude: 48.0, longitude: 2.0, zoom: 11), size: .init(width: 300, height: 400))

        let oldLookup = Task { await store.viewportDidSettle(oldViewport) }
        try? await Task.sleep(for: .milliseconds(10))
        let newLookup = Task { await store.viewportDidSettle(newViewport) }
        await oldLookup.value
        await newLookup.value

        XCTAssertEqual(store.document.location.city, "NEW CITY")
        XCTAssertEqual(store.document.location.latitude, 48.0)
        XCTAssertEqual(store.document.location.longitude, 2.0)
    }

    @MainActor
    func testZoomingIntoDistrictLevelResolvesMissingDistrictAtSameCenter() async {
        let resolved = PlaceSuggestion(name: "Shinjuku, Tokyo, Japan", district: "Shinjuku", city: "Tokyo", country: "Japan", countryCode: "JP", continent: "Asia", latitude: 35.68, longitude: 139.69, zoom: 13)
        let geocoder = RecordingGeocoder(result: resolved)
        let store = makeStore(document: .tokyo, geocoder: geocoder)
        store.select(.init(name: "Tokyo, Japan", city: "Tokyo", country: "Japan", countryCode: "JP", continent: "Asia", latitude: 35.68, longitude: 139.69, zoom: 11))
        let viewport = MapViewport(camera: .init(latitude: 35.68, longitude: 139.69, zoom: 13), size: .init(width: 300, height: 400))

        await store.viewportDidSettle(viewport)
        await store.viewportDidSettle(viewport)

        let reverseCount = await geocoder.reverseCount
        XCTAssertEqual(store.document.location.district, "SHINJUKU")
        XCTAssertEqual(reverseCount, 1)
    }

    @MainActor
    func testReverseGeocodeFailurePreservesExistingLocationState() async {
        let original = PosterDocument.tokyo
        let store = makeStore(document: original, geocoder: StubGeocoder(reverseResult: nil))
        let viewport = MapViewport(camera: .init(latitude: 1, longitude: 2, zoom: 11), size: .init(width: 300, height: 400))

        await store.viewportDidSettle(viewport)

        XCTAssertEqual(store.document.location, original.location)
        XCTAssertNil(store.errorMessage)
    }

#if canImport(MapLibre)
    @MainActor
    func testProgrammaticMapUpdateSuppressesViewportCallbacks() {
        let parent = MapLibreMapView(document: .tokyo, onViewportChange: { _ in XCTFail("Programmatic update must not report a viewport change") }, onViewportSettled: { _ in XCTFail("Programmatic update must not settle the viewport") }, onFailure: { _ in })
        let coordinator = MapLibreMapView.Coordinator(parent: parent)

        coordinator.isApplyingDocument = true

        XCTAssertFalse(coordinator.shouldReportViewportChanges)
    }
#endif

    func testUnknownThemeFallsBackToNoir() {
        var document = PosterDocument.tokyo
        document.themeID = "removed-theme"
        document.normalize()
        XCTAssertEqual(document.themeID, PosterTheme.defaultID)
    }

    func testLegacyThemeIdentifiersMigrate() {
        var midnight = PosterDocument.tokyo
        midnight.themeID = "midnight"
        midnight.normalize()
        XCTAssertEqual(midnight.themeID, "midnight_blue")

        var oxide = PosterDocument.tokyo
        oxide.themeID = "oxide"
        oxide.normalize()
        XCTAssertEqual(oxide.themeID, "heatwave")
    }

    func testCameraIsClampedAndBearingIsPreserved() {
        var document = PosterDocument.tokyo
        document.camera = .init(latitude: 100, longitude: -200, zoom: 50, bearing: 32)
        document.normalize()
        XCTAssertEqual(document.camera.latitude, 90)
        XCTAssertEqual(document.camera.longitude, -180)
        XCTAssertEqual(document.camera.zoom, 22)
        XCTAssertEqual(document.camera.bearing, 32)
    }

    func testNegativeBearingIsNormalized() {
        var document = PosterDocument.tokyo
        document.camera.bearing = -45
        document.normalize()
        XCTAssertEqual(document.camera.bearing, 315)
    }

    func testAllPresetSizesStayInsideBudget() {
        XCTAssertEqual(PosterLayout.allCases.count, 6)
        for layout in PosterLayout.allCases {
            XCTAssertLessThanOrEqual(layout.pixelSize.width * layout.pixelSize.height, 12_000_000)
        }
        XCTAssertEqual(PosterLayout.square.pixelSize, .init(width: 2400, height: 2400))
        XCTAssertEqual(PosterLayout.widescreen.title, "9:16")
        XCTAssertEqual(PosterLayout.widescreen.aspectRatio, 9.0 / 16.0)
        XCTAssertEqual(PosterLayout.widescreen.pixelSize, .init(width: 1800, height: 3200))
    }

    func testDefaultPosterUsesA4Layout() {
        XCTAssertEqual(PosterDocument.tokyo.layout, .a4Portrait)
    }

    func testAllReferenceThemesAreAvailableWithDisplayNames() {
        XCTAssertEqual(PosterTheme.all.count, 19)
        XCTAssertEqual(Set(PosterTheme.all.map(\.id)).count, 19)
        XCTAssertTrue(PosterTheme.all.allSatisfy { !$0.name.isEmpty })
    }

    func testDraftRoundTrip() throws {
        let document = PosterDocument.tokyo
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(PosterDocument.self, from: data), document)
    }

    func testLiveMapStyleIsBundled() {
        XCTAssertEqual(MapServiceConfiguration.styleURL.lastPathComponent, "loci-map-style.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: MapServiceConfiguration.styleURL.path))
    }

    func testExportAttributionCoversMapSources() {
        XCTAssertTrue(MapServiceConfiguration.exportAttribution.localizedCaseInsensitiveContains("OpenStreetMap"))
        XCTAssertTrue(MapServiceConfiguration.exportAttribution.localizedCaseInsensitiveContains("OpenMapTiles"))
        XCTAssertTrue(MapServiceConfiguration.compactMapAttribution.contains("ODbL"))
        XCTAssertEqual(MapServiceConfiguration.posterSignature, "©Loci")
    }

    func testViewportUsesPointSizeToCalculateExportScale() {
        let viewport = MapViewport(camera: PosterDocument.tokyo.camera, size: .init(width: 300, height: 375))
        XCTAssertTrue(viewport.isValid)
        XCTAssertEqual(viewport.outputScale(for: .init(width: 1920, height: 2400)), 6.4, accuracy: 0.0001)
    }

    func testInvalidViewportCannotProduceScale() {
        let viewport = MapViewport(camera: PosterDocument.tokyo.camera, size: .zero)
        XCTAssertFalse(viewport.isValid)
        XCTAssertEqual(viewport.outputScale(for: .init(width: 1920, height: 2400)), 0)
    }

    func testCompositorProducesExactPixelDimensionsAndBothFades() throws {
        var document = PosterDocument.tokyo
        document.typography = .init(cityVisible: false, countryVisible: false, subtitleVisible: false, cityIsUserEdited: false, countryIsUserEdited: false, subtitle: "")
        let map = UIGraphicsImageRenderer(size: .init(width: 100, height: 125)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(.init(x: 0, y: 0, width: 100, height: 125))
        }
        let image = try CoreGraphicsCompositor().render(map: map, document: document, output: .init(width: 100, height: 125))
        XCTAssertEqual(image.cgImage?.width, 100)
        XCTAssertEqual(image.cgImage?.height, 125)
        let top = try pixel(in: image, x: 50, y: 0)
        let middle = try pixel(in: image, x: 50, y: 50)
        let bottom = try pixel(in: image, x: 50, y: 124)
        XCTAssertLessThan(top.red, middle.red)
        XCTAssertLessThan(bottom.red, middle.red)
    }

    private func pixel(in image: UIImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard let cgImage = image.cgImage, let provider = cgImage.dataProvider, let data = provider.data else {
            throw LociError.renderFailed
        }
        let bytes = CFDataGetBytePtr(data)!
        let offset = y * cgImage.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    @MainActor
    private func makeStore(document: PosterDocument, geocoder: any GeocodingClient, offlineGeocoder: any OfflineGeocodingClient = EmptyOfflineGeocodingClient()) -> PosterEditorStore {
        PosterEditorStore(document: document, drafts: StubDraftRepository(), geocoder: geocoder, offlineGeocoder: offlineGeocoder, exporter: StubExportService(), currentLocation: StubCurrentLocationClient(), photoLibrary: StubPhotoLibrarySaver())
    }

    private func makeOfflineGazetteer() throws -> OfflineGazetteer {
        let resources = offlineResourceDirectory()
        return try OfflineGazetteer(countryURL: resources.appending(path: "countries.json"), cityDatabaseURL: resources.appending(path: "cities.sqlite"))
    }

    private func offlineResourceDirectory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Loci/Resources/OfflineGeodata")
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var data = Data()
    private static var count = 0
    private static var request: URLRequest?
    private static var statusCode = 200
    private static var failure: Error?

    static var requestCount: Int { lock.withLock { count } }
    static var lastRequest: URLRequest? { lock.withLock { request } }

    static func reset(responseData: Data, statusCode: Int = 200, error: Error? = nil) {
        lock.withLock { data = responseData; count = 0; request = nil; Self.statusCode = statusCode; failure = error }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let values = Self.lock.withLock { Self.count += 1; Self.request = request; return (Self.data, Self.statusCode, Self.failure) }
        if let failure = values.2 { client?.urlProtocol(self, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: values.1, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: values.0)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct StubGeocoder: GeocodingClient {
    let reverseResult: PlaceSuggestion?
    func search(query: String) async throws -> [PlaceSuggestion] { [] }
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion {
        guard let reverseResult else { throw LociError.noResults }
        return reverseResult
    }
}

private struct DelayedGeocoder: GeocodingClient {
    func search(query: String) async throws -> [PlaceSuggestion] { [] }
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion {
        try? await Task.sleep(for: latitude < 40 ? .milliseconds(150) : .milliseconds(10))
        let city = latitude < 40 ? "Old City" : "New City"
        return .init(name: city, city: city, country: "Country", latitude: latitude, longitude: longitude, zoom: 11)
    }
}

private actor RecordingGeocoder: GeocodingClient {
    let result: PlaceSuggestion
    private(set) var reverseCount = 0
    init(result: PlaceSuggestion) { self.result = result }
    func search(query: String) async throws -> [PlaceSuggestion] { [] }
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion { reverseCount += 1; return result }
}

private struct StubOfflineGeocoder: OfflineGeocodingClient {
    let result: PlaceSuggestion?
    func preload() async throws {}
    func resolve(latitude: Double, longitude: Double, zoom: Double) async throws -> PlaceSuggestion? { result }
}

private struct StubDraftRepository: DraftRepository {
    func load() throws -> PosterDocument? { nil }
    func save(_ document: PosterDocument) throws {}
}

private struct StubExportService: ExportService {
    func export(document: PosterDocument, viewport: MapViewport) async throws -> URL { throw LociError.renderFailed }
}

private struct StubCurrentLocationClient: CurrentLocationClient {
    func locate() async throws -> PlaceSuggestion { throw LociError.locationUnavailable }
}

private struct StubPhotoLibrarySaver: PhotoLibrarySaver {
    func saveImage(at url: URL) async throws {}
}

private func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Any, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
