import Foundation
import Photos
import UIKit

struct UserDefaultsDraftRepository: DraftRepository {
    private let key = "loci.latest-draft"

    func load() throws -> PosterDocument? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var document = try JSONDecoder().decode(PosterDocument.self, from: data)
        document.normalize()
        return document
    }

    func save(_ document: PosterDocument) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(document), forKey: key)
    }
}

actor NominatimGeocodingClient: GeocodingClient {
    private struct CacheEntry<Value: Sendable>: Sendable {
        let value: Value
        let storedAt: Date
    }

    private let endpoint: URL
    private let session: URLSession
    private let cacheLifetime: TimeInterval
    private let minimumRequestInterval: Duration
    private var searchCache: [String: CacheEntry<[PlaceSuggestion]>] = [:]
    private var reverseCache: [String: CacheEntry<PlaceSuggestion>] = [:]
    private var searchRequests: [String: Task<[PlaceSuggestion], Error>] = [:]
    private var reverseRequests: [String: Task<PlaceSuggestion, Error>] = [:]
    private var lastRequest: ContinuousClock.Instant?

    init(endpoint: URL = URL(string: "https://nominatim.openstreetmap.org")!, session: URLSession = .shared, cacheLifetime: TimeInterval = 86_400, minimumRequestInterval: Duration = .seconds(1)) {
        self.endpoint = endpoint
        self.session = session
        self.cacheLifetime = cacheLifetime
        self.minimumRequestInterval = minimumRequestInterval
    }

    func search(query: String) async throws -> [PlaceSuggestion] {
        let lookup = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lookup.count >= 2 else { return [] }
        let key = NominatimResponseParser.normalized(lookup)
        if let cached = searchCache[key], Date().timeIntervalSince(cached.storedAt) < cacheLifetime { return cached.value }
        if let pending = searchRequests[key] { return try await pending.value }

        let task = Task { try await performSearch(query: lookup) }
        searchRequests[key] = task
        defer { searchRequests[key] = nil }
        let results = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        searchCache[key] = .init(value: results, storedAt: .now)
        return results
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw LociError.invalidCoordinates }
        let key = String(format: "%.4f,%.4f", latitude, longitude)
        if let cached = reverseCache[key], Date().timeIntervalSince(cached.storedAt) < cacheLifetime { return cached.value }
        if let pending = reverseRequests[key] { return try await pending.value }

        let task = Task { try await performReverseGeocode(latitude: latitude, longitude: longitude) }
        reverseRequests[key] = task
        defer { reverseRequests[key] = nil }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        reverseCache[key] = .init(value: result, storedAt: .now)
        return result
    }

    private func performSearch(query: String) async throws -> [PlaceSuggestion] {
        let url = try makeURL(path: "search", items: [
            .init(name: "format", value: "jsonv2"), .init(name: "addressdetails", value: "1"),
            .init(name: "limit", value: "6"), .init(name: "q", value: query)
        ])
        let data = try await fetch(url)
        return try NominatimResponseParser.parseSearch(data: data, query: query)
    }

    private func performReverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceSuggestion {
        let url = try makeURL(path: "reverse", items: [
            .init(name: "format", value: "jsonv2"), .init(name: "addressdetails", value: "1"),
            .init(name: "zoom", value: "14"), .init(name: "lat", value: String(latitude)),
            .init(name: "lon", value: String(longitude))
        ])
        let data = try await fetch(url)
        return try NominatimResponseParser.parseReverse(data: data)
    }

    private func makeURL(path: String, items: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: endpoint.appending(path: path), resolvingAgainstBaseURL: false) else { throw LociError.unavailableConfiguration }
        components.queryItems = items
        guard let url = components.url else { throw LociError.unavailableConfiguration }
        return url
    }

    private func fetch(_ url: URL) async throws -> Data {
        let clock = ContinuousClock()
        while true {
            try Task.checkCancellation()
            let now = clock.now
            if let lastRequest {
                let nextAllowed = lastRequest.advanced(by: minimumRequestInterval)
                if now < nextAllowed { try await clock.sleep(until: nextAllowed); continue }
            }
            lastRequest = now
            break
        }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 16)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("Loci/1.0 (iOS map poster app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}

enum NominatimResponseParser {
    private struct Entry: Decodable {
        let placeID: Int?
        let latitude: String?
        let longitude: String?
        let name: String?
        let displayName: String?
        let category: String?
        let type: String?
        let address: [String: String]?

        enum CodingKeys: String, CodingKey {
            case placeID = "place_id", latitude = "lat", longitude = "lon", name
            case displayName = "display_name", category, type, address
        }
    }

    static func parseSearch(data: Data, query: String) throws -> [PlaceSuggestion] {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        let ranked = entries.compactMap(makeSuggestion).sorted { lhs, rhs in
            score(lhs, query: query) < score(rhs, query: query)
        }
        var unique: [PlaceSuggestion] = []
        for suggestion in ranked {
            let primaryName = normalized(suggestion.name.components(separatedBy: ",").first ?? suggestion.name)
            let isDuplicate = unique.contains { existing in
                let existingName = normalized(existing.name.components(separatedBy: ",").first ?? existing.name)
                return primaryName == existingName && suggestion.countryCode == existing.countryCode && distanceMeters(suggestion, existing) <= 150
            }
            if !isDuplicate { unique.append(suggestion) }
        }
        return unique
    }

    static func parseReverse(data: Data) throws -> PlaceSuggestion {
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        guard let suggestion = makeSuggestion(entry) else { throw LociError.noResults }
        return suggestion
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func makeSuggestion(_ entry: Entry) -> PlaceSuggestion? {
        guard let latText = entry.latitude, let lonText = entry.longitude, let latitude = Double(latText), let longitude = Double(lonText),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let address = entry.address ?? [:]
        let district = first(address, ["city_district", "borough", "suburb", "quarter", "neighbourhood"])
        let city = first(address, ["city", "town", "village", "municipality", "hamlet"])
        let administrativeArea = first(address, ["state", "region", "province", "county", "state_district"])
        let country = first(address, ["country"])
        let countryCode = first(address, ["country_code"]).uppercased()
        let displayName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !displayName.isEmpty else { return nil }
        let administrativeTypes: Set<String> = ["administrative", "country", "state", "region", "province", "county", "city", "town", "village", "municipality", "borough", "suburb", "quarter", "neighbourhood"]
        let isAdministrative = entry.category == "boundary" || entry.category == "place" || administrativeTypes.contains(entry.type ?? "")
        return .init(
            id: entry.placeID.map(String.init) ?? "\(latitude),\(longitude)", name: displayName,
            district: district, city: city, administrativeArea: administrativeArea, country: country,
            countryCode: countryCode, continent: ContinentResolver.continent(countryCode: countryCode),
            isAdministrative: isAdministrative,
            latitude: latitude, longitude: longitude, zoom: suggestedZoom(type: entry.type)
        )
    }

    private static func score(_ suggestion: PlaceSuggestion, query: String) -> (Int, Int, String) {
        let needle = normalized(query)
        let label = normalized(suggestion.name.components(separatedBy: ",").first ?? suggestion.name)
        let administrativeValues = [suggestion.district, suggestion.city, suggestion.administrativeArea, suggestion.country].map(normalized)
        let relevance: Int
        if label == needle { relevance = 0 }
        else if label.hasPrefix(needle) { relevance = 1 }
        else if administrativeValues.contains(needle) { relevance = 2 }
        else if label.contains(needle) || administrativeValues.contains(where: { $0.contains(needle) }) { relevance = 3 }
        else { relevance = 4 }
        let administrativePenalty = suggestion.isAdministrative ? 0 : 1
        return (relevance, administrativePenalty, normalized(suggestion.name))
    }

    private static func first(_ address: [String: String], _ keys: [String]) -> String {
        for key in keys { if let value = address[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value } }
        return ""
    }

    private static func suggestedZoom(type: String?) -> Double {
        switch type {
        case "country": 5
        case "state", "region", "province": 7
        case "city", "town", "village", "municipality": 11
        case "borough", "suburb", "quarter", "neighbourhood": 13
        default: 12
        }
    }

    private static func distanceMeters(_ lhs: PlaceSuggestion, _ rhs: PlaceSuggestion) -> Double {
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let lhsLatitude = lhs.latitude * .pi / 180
        let rhsLatitude = rhs.latitude * .pi / 180
        let a = pow(sin(latitudeDelta / 2), 2) + cos(lhsLatitude) * cos(rhsLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

enum ContinentResolver {
    private static let africa = Set("DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW".split(separator: " ").map(String.init))
    private static let asia = Set("AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KW KG LA LB MO MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE".split(separator: " ").map(String.init))
    private static let europe = Set("AL AD AT BY BE BA BG HR CZ DK EE FI FR DE GR HU IS IE IT LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SE CH UA GB VA".split(separator: " ").map(String.init))
    private static let northAmerica = Set("AI AG AW BS BB BZ BM BQ CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI".split(separator: " ").map(String.init))
    private static let southAmerica = Set("AR BO BR CL CO EC GY PY PE SR UY VE".split(separator: " ").map(String.init))
    private static let oceania = Set("AS AU CX CC CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV UM VU WF".split(separator: " ").map(String.init))

    static func continent(countryCode: String) -> String {
        let code = countryCode.uppercased()
        if africa.contains(code) { return "Africa" }
        if asia.contains(code) { return "Asia" }
        if europe.contains(code) { return "Europe" }
        if northAmerica.contains(code) { return "North America" }
        if southAmerica.contains(code) { return "South America" }
        if oceania.contains(code) { return "Oceania" }
        if code == "AQ" { return "Antarctica" }
        return ""
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

struct CoreGraphicsCompositor: PosterCompositor {
    func render(map: UIImage, document: PosterDocument, output: CGSize) throws -> UIImage {
        let theme = PosterTheme.all.first(where: { $0.id == document.themeID }) ?? PosterTheme.all[0]
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { context in
            map.draw(in: .init(origin: .zero, size: output))
            let topGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(hex: theme.background).withAlphaComponent(PosterFade.opacity).cgColor, UIColor.clear.cgColor] as CFArray,
                locations: [0, 1]
            )!
            context.cgContext.drawLinearGradient(topGradient, start: .init(x: 0, y: 0), end: .init(x: 0, y: output.height * PosterFade.topFraction), options: [])
            let bottomGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.clear.cgColor, UIColor(hex: theme.background).withAlphaComponent(PosterFade.opacity).cgColor] as CFArray,
                locations: [0.42, 1]
            )!
            context.cgContext.drawLinearGradient(bottomGradient, start: .init(x: 0, y: output.height * (1 - PosterFade.bottomFraction)), end: .init(x: 0, y: output.height), options: [])
            let margin = output.width * 0.08
            let color = UIColor(hex: theme.ink)
            let locationText = document.locationPresentation
            if document.typography.cityVisible { draw(locationText.primary, font: .monospacedSystemFont(ofSize: output.width * 0.105, weight: .bold), color: color, rect: .init(x: margin, y: output.height * PosterTypographyLayout.cityYFraction, width: output.width - margin * 2, height: output.height * 0.10), alignment: .center, kern: output.width * 0.006) }
            if document.typography.countryVisible { draw(locationText.secondary, font: .monospacedSystemFont(ofSize: output.width * 0.030, weight: .medium), color: color.withAlphaComponent(0.74), rect: .init(x: margin, y: output.height * PosterTypographyLayout.countryYFraction, width: output.width - margin * 2, height: output.height * 0.04), alignment: .center, kern: output.width * 0.004) }
            drawSeparator(in: context.cgContext, output: output, color: color)
            if document.typography.subtitleVisible { draw(document.typography.subtitle.uppercased(), font: .monospacedSystemFont(ofSize: output.width * 0.020, weight: .regular), color: color.withAlphaComponent(0.64), rect: .init(x: margin, y: output.height * PosterTypographyLayout.subtitleYFraction, width: output.width - margin * 2, height: output.height * 0.03), alignment: .center, kern: output.width * 0.002) }
            draw(String(format: "%.4f°  %.4f°", document.camera.latitude, document.camera.longitude), font: .monospacedSystemFont(ofSize: output.width * 0.013, weight: .regular), color: color.withAlphaComponent(0.48), rect: .init(x: margin, y: output.height * PosterTypographyLayout.coordinatesYFraction, width: output.width - margin * 2, height: output.height * 0.025), alignment: .center)
            let footerY = output.height * PosterTypographyLayout.footerYFraction
            draw(MapServiceConfiguration.compactMapAttribution, font: .monospacedSystemFont(ofSize: output.width * 0.007, weight: .regular), color: color.withAlphaComponent(0.28), rect: .init(x: output.width * 0.025, y: footerY, width: output.width * 0.62, height: output.height * 0.02))
            draw(MapServiceConfiguration.posterSignature, font: .systemFont(ofSize: output.width * 0.009, weight: .medium), color: color.withAlphaComponent(0.52), rect: .init(x: output.width * 0.68, y: footerY, width: output.width * 0.295, height: output.height * 0.02), alignment: .right)
        }
    }

    private func drawSeparator(in context: CGContext, output: CGSize, color: UIColor) {
        let width = output.width * PosterTypographyLayout.separatorWidthFraction
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.28, 0.72, 1])!
        let y = output.height * PosterTypographyLayout.separatorYFraction
        let startX = (output.width - width) / 2
        context.saveGState()
        context.clip(to: .init(x: startX, y: y, width: width, height: max(1, output.width * 0.001)))
        context.drawLinearGradient(gradient, start: .init(x: startX, y: y), end: .init(x: startX + width, y: y), options: [])
        context.restoreGState()
    }

    private func draw(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern])
    }
}

struct SystemPhotoLibrarySaver: PhotoLibrarySaver {
    func saveImage(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw LociError.photoAccessDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        } catch {
            throw LociError.photoSaveFailed
        }
    }
}

struct LocalExportService: ExportService {
    let renderer: MapRenderer
    let compositor: PosterCompositor

    func export(document: PosterDocument, viewport: MapViewport) async throws -> URL {
        let size = document.layout.pixelSize
        guard size.width * size.height <= 12_000_000 else { throw LociError.outputTooLarge }
        let map = try await renderer.snapshot(document: document, size: size, viewport: viewport)
        let output = try compositor.render(map: map, document: document, output: size)
        guard let data = output.pngData() else { throw LociError.renderFailed }
        let url = FileManager.default.temporaryDirectory.appending(path: "Loci-\(document.title.lowercased())-\(UUID().uuidString.prefix(8)).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}
