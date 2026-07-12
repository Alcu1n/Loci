import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor OfflineGazetteer: OfflineGeocodingClient {
    private struct CountryRecord: Decodable {
        let code: String
        let name: String
        let continent: String
        let polygons: [[[[Double]]]]
    }

    private struct Country {
        struct Polygon {
            let rings: [[[Double]]]
            let minLatitude: Double
            let maxLatitude: Double
        }

        let code: String
        let name: String
        let continent: String
        let polygons: [Polygon]
    }

    private let countryURL: URL
    private let cityDatabaseURL: URL
    private var countries: [Country]?
    private var database: OpaquePointer?

    init(countryURL: URL, cityDatabaseURL: URL) throws {
        guard FileManager.default.fileExists(atPath: countryURL.path), FileManager.default.fileExists(atPath: cityDatabaseURL.path) else {
            throw LociError.unavailableConfiguration
        }
        self.countryURL = countryURL
        self.cityDatabaseURL = cityDatabaseURL
    }

    static func live(bundle: Bundle = .main) throws -> OfflineGazetteer {
        guard let countryURL = bundle.url(forResource: "countries", withExtension: "json"),
              let cityDatabaseURL = bundle.url(forResource: "cities", withExtension: "sqlite") else {
            throw LociError.unavailableConfiguration
        }
        return try OfflineGazetteer(countryURL: countryURL, cityDatabaseURL: cityDatabaseURL)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func preload() throws {
        try loadCountriesIfNeeded()
        try openDatabaseIfNeeded()
    }

    func resolve(latitude: Double, longitude: Double, zoom: Double) throws -> PlaceSuggestion? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw LociError.invalidCoordinates }
        try loadCountriesIfNeeded()
        guard let country = country(at: latitude, longitude: longitude) else { return nil }

        var city: CityResult?
        var district: CityResult?
        if zoom >= 7 {
            try openDatabaseIfNeeded()
            city = try nearestCity(latitude: latitude, longitude: longitude, countryCode: country.code, zoom: zoom >= 12 ? 11 : zoom)
            if zoom >= 12 {
                district = try nearestCity(latitude: latitude, longitude: longitude, countryCode: country.code, zoom: 12)
            }
        }

        let districtName = district?.name != city?.name ? district?.name : nil
        let label = [districtName, city?.name, city?.administrativeArea, country.name].compactMap { $0 }.filter { !$0.isEmpty }.removingAdjacentDuplicates().joined(separator: ", ")
        return PlaceSuggestion(
            id: "offline:\(country.code):\(city?.id ?? 0):\(district?.id ?? 0)", name: label,
            district: districtName ?? "", city: city?.name ?? district?.name ?? "", administrativeArea: city?.administrativeArea ?? district?.administrativeArea ?? "",
            country: country.name, countryCode: country.code, continent: country.continent,
            latitude: latitude, longitude: longitude, zoom: zoom
        )
    }

    private func loadCountriesIfNeeded() throws {
        guard countries == nil else { return }
        let records = try JSONDecoder().decode([CountryRecord].self, from: Data(contentsOf: countryURL, options: .mappedIfSafe))
        countries = records.map { record in
            Country(
                code: record.code, name: record.name, continent: record.continent,
                polygons: record.polygons.compactMap { rings in
                    let latitudes = rings.first?.compactMap { $0.count == 2 ? $0[1] : nil } ?? []
                    guard let minimum = latitudes.min(), let maximum = latitudes.max() else { return nil }
                    return .init(rings: rings, minLatitude: minimum, maxLatitude: maximum)
                }
            )
        }
    }

    private func country(at latitude: Double, longitude: Double) -> Country? {
        countries?.first { country in
            country.polygons.contains { polygon in
                guard (polygon.minLatitude...polygon.maxLatitude).contains(latitude),
                      let outer = polygon.rings.first,
                      contains(latitude: latitude, longitude: longitude, ring: outer) else { return false }
                return !polygon.rings.dropFirst().contains { contains(latitude: latitude, longitude: longitude, ring: $0) }
            }
        }
    }

    private func contains(latitude: Double, longitude: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3, ring[0].count == 2 else { return false }
        var inside = false
        var previous = ring[ring.count - 1]
        var previousLongitude = longitudeNear(previous[0], reference: ring[0][0])
        let testLongitude = longitudeNear(longitude, reference: ring[0][0])
        for current in ring {
            guard current.count == 2, previous.count == 2 else { previous = current; continue }
            let currentLongitude = longitudeNear(current[0], reference: previousLongitude)
            let crosses = (current[1] > latitude) != (previous[1] > latitude)
            if crosses {
                let intersection = (previousLongitude - currentLongitude) * (latitude - current[1]) / (previous[1] - current[1]) + currentLongitude
                if testLongitude < intersection { inside.toggle() }
            }
            previous = current
            previousLongitude = currentLongitude
        }
        return inside
    }

    private func longitudeNear(_ value: Double, reference: Double) -> Double {
        var adjusted = value
        while adjusted - reference > 180 { adjusted -= 360 }
        while adjusted - reference < -180 { adjusted += 360 }
        return adjusted
    }

    private func openDatabaseIfNeeded() throws {
        guard database == nil else { return }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(cityDatabaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw LociError.unavailableConfiguration
        }
        database = handle
    }

    private struct CityResult {
        let id: Int
        let name: String
        let administrativeArea: String
        let latitude: Double
        let longitude: Double
    }

    private func nearestCity(latitude: Double, longitude: Double, countryCode: String, zoom: Double) throws -> CityResult? {
        guard let database else { return nil }
        let searchRadius = zoom >= 12 ? 1.0 : 3.0
        let longitudeRadius = min(12, searchRadius / max(0.2, cos(latitude * .pi / 180)))
        let longitudeRanges = wrappedLongitudeRanges(center: longitude, radius: longitudeRadius)
        let firstRange = longitudeRanges[0]
        let secondRange = longitudeRanges.count == 2 ? longitudeRanges[1] : (181.0...181.0)
        let orderExpression = zoom >= 12
            ? "((c.latitude - ?8) * (c.latitude - ?8)) + ((MIN(ABS(c.longitude - ?9), 360 - ABS(c.longitude - ?9)) * ?10) * (MIN(ABS(c.longitude - ?9), 360 - ABS(c.longitude - ?9)) * ?10))"
            : "(((c.latitude - ?8) * (c.latitude - ?8)) + ((MIN(ABS(c.longitude - ?9), 360 - ABS(c.longitude - ?9)) * ?10) * (MIN(ABS(c.longitude - ?9), 360 - ABS(c.longitude - ?9)) * ?10))) / MAX(c.population, 5000)"
        let sql = """
        SELECT c.id, c.name, c.admin_name, c.latitude, c.longitude
        FROM city_index i JOIN cities c ON c.id = i.id
        WHERE i.min_latitude BETWEEN ?1 AND ?2
          AND (i.min_longitude BETWEEN ?3 AND ?4 OR i.min_longitude BETWEEN ?5 AND ?6)
          AND c.country_code = ?7
        ORDER BY \(orderExpression) ASC,
                 c.population DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw LociError.unavailableConfiguration }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, latitude - searchRadius)
        sqlite3_bind_double(statement, 2, latitude + searchRadius)
        sqlite3_bind_double(statement, 3, firstRange.lowerBound)
        sqlite3_bind_double(statement, 4, firstRange.upperBound)
        sqlite3_bind_double(statement, 5, secondRange.lowerBound)
        sqlite3_bind_double(statement, 6, secondRange.upperBound)
        sqlite3_bind_text(statement, 7, countryCode, -1, sqliteTransient)
        sqlite3_bind_double(statement, 8, latitude)
        sqlite3_bind_double(statement, 9, longitude)
        sqlite3_bind_double(statement, 10, cos(latitude * .pi / 180))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let result = CityResult(
            id: Int(sqlite3_column_int64(statement, 0)),
            name: String(cString: sqlite3_column_text(statement, 1)),
            administrativeArea: String(cString: sqlite3_column_text(statement, 2)),
            latitude: sqlite3_column_double(statement, 3), longitude: sqlite3_column_double(statement, 4)
        )
        let maximumDistance = zoom >= 12 ? 60_000.0 : 250_000.0
        return distanceMeters(latitude, longitude, result.latitude, result.longitude) <= maximumDistance ? result : nil
    }

    private func wrappedLongitudeRanges(center: Double, radius: Double) -> [ClosedRange<Double>] {
        let lower = center - radius
        let upper = center + radius
        if lower < -180 { return [(-180...upper), ((lower + 360)...180)] }
        if upper > 180 { return [(lower...180), (-180...(upper - 360))] }
        return [lower...upper]
    }

    private func distanceMeters(_ latitude: Double, _ longitude: Double, _ otherLatitude: Double, _ otherLongitude: Double) -> Double {
        let latitudeDelta = (otherLatitude - latitude) * .pi / 180
        let longitudeDelta = (otherLongitude - longitude) * .pi / 180
        let firstLatitude = latitude * .pi / 180
        let secondLatitude = otherLatitude * .pi / 180
        let a = pow(sin(latitudeDelta / 2), 2) + cos(firstLatitude) * cos(secondLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        reduce(into: []) { result, value in
            if result.last?.caseInsensitiveCompare(value) != .orderedSame { result.append(value) }
        }
    }
}
