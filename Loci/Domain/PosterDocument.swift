import Foundation

struct PosterDocument: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var id: UUID
    var schemaVersion: Int
    var title: String
    var updatedAt: Date
    var location: PosterLocation
    var camera: PosterCamera
    var layout: PosterLayout
    var themeID: String
    var layerVisibility: LayerVisibility
    var typography: PosterTypography

    static let shanghai = PosterDocument(
        id: UUID(), schemaVersion: currentSchemaVersion, title: "SHANGHAI", updatedAt: .now,
        location: .init(latitude: 31.2304, longitude: 121.4737, resolvedName: "Shanghai, China", city: "SHANGHAI", administrativeArea: "SHANGHAI", country: "CHINA", countryCode: "CN", continent: "ASIA"),
        camera: .init(latitude: 31.2304, longitude: 121.4737, zoom: 13), layout: .a4Portrait,
        themeID: PosterTheme.defaultID, layerVisibility: .all, typography: .default
    )

    static let tokyo = PosterDocument(
        id: UUID(), schemaVersion: currentSchemaVersion, title: "TOKYO", updatedAt: .now,
        location: .init(latitude: 35.6762, longitude: 139.6503, resolvedName: "Tokyo, Japan", city: "TOKYO", country: "JAPAN"),
        camera: .init(latitude: 35.6762, longitude: 139.6503, zoom: 11), layout: .a4Portrait,
        themeID: PosterTheme.defaultID, layerVisibility: .all, typography: .default
    )
}

struct PosterLocation: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var resolvedName: String?
    var district: String?
    var city: String?
    var administrativeArea: String?
    var country: String?
    var countryCode: String?
    var continent: String?

    init(latitude: Double, longitude: Double, resolvedName: String? = nil, district: String? = nil, city: String? = nil, administrativeArea: String? = nil, country: String? = nil, countryCode: String? = nil, continent: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.resolvedName = resolvedName
        self.district = district
        self.city = city
        self.administrativeArea = administrativeArea
        self.country = country
        self.countryCode = countryCode
        self.continent = continent
    }
}

struct LocationPresentation: Equatable, Sendable {
    let primary: String
    let secondary: String
}
struct AutomaticLocationAnchor: Codable, Equatable, Sendable {
    var name: String?
    var administrativeArea: String?
    var country: String?
    var countryCode: String?
    var nameIsCity: Bool? = nil
}
struct PosterCamera: Codable, Equatable, Sendable { var latitude: Double; var longitude: Double; var zoom: Double; var bearing: Double = 0 }
struct LayerVisibility: Codable, Equatable, Sendable { var water: Bool; var green: Bool; var buildings: Bool; var roads: Bool; static let all = Self(water: true, green: true, buildings: true, roads: true) }
struct PosterTypography: Codable, Equatable, Sendable {
    var cityVisible: Bool
    var countryVisible: Bool
    var subtitleVisible: Bool
    var cityIsUserEdited: Bool
    var countryIsUserEdited: Bool
    var subtitle: String
    var cityOverrideAnchor: AutomaticLocationAnchor? = nil
    var countryOverrideAnchor: AutomaticLocationAnchor? = nil
    static let `default` = Self(cityVisible: true, countryVisible: true, subtitleVisible: true, cityIsUserEdited: false, countryIsUserEdited: false, subtitle: "A PLACE TO REMEMBER")
}

enum PosterLayout: String, Codable, CaseIterable, Identifiable, Sendable { case socialPortrait, posterPortrait, square, landscape, widescreen, a4Portrait; var id: String { rawValue }
    var title: String { switch self { case .socialPortrait: "4:5"; case .posterPortrait: "2:3"; case .square: "1:1"; case .landscape: "3:2"; case .widescreen: "9:16"; case .a4Portrait: "A4" } }
    var aspectRatio: CGFloat { switch self { case .socialPortrait: 4.0 / 5.0; case .posterPortrait: 2.0 / 3.0; case .square: 1; case .landscape: 3.0 / 2.0; case .widescreen: 9.0 / 16.0; case .a4Portrait: 210.0 / 297.0 } }
    var pixelSize: CGSize { switch self { case .socialPortrait: .init(width: 1920, height: 2400); case .posterPortrait: .init(width: 2000, height: 3000); case .square: .init(width: 2400, height: 2400); case .landscape: .init(width: 3000, height: 2000); case .widescreen: .init(width: 1800, height: 3200); case .a4Portrait: .init(width: 2100, height: 2970) } }
}

struct PosterTheme: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let background: String
    let land: String
    let landcover: String
    let water: String
    let parks: String
    let roads: String
    let roadsHigh: String
    let roadsMid: String
    let roadsLow: String
    let roadsPath: String
    let roadOutline: String
    let buildings: String
    let rail: String
    let ink: String

    var thumbnailAssetName: String { name.lowercased() }

    static let defaultID = "midnight_blue"
    static let all: [Self] = [
        .init(id: "carrara", name: "Alabaster", background: "F4F1EA", land: "F4F1EA", landcover: "ECE7DD", water: "C7CDD0", parks: "E6E3D8", roads: "3A3631", roadsHigh: "565049", roadsMid: "6E675E", roadsLow: "8B8378", roadsPath: "A89F92", roadOutline: "F4F1EA", buildings: "E0DACD", rail: "2E2A26", ink: "2E2A26"),
        .init(id: "blush", name: "Petal", background: "F9F1F0", land: "F9F1F0", landcover: "F1E1E0", water: "E0BFC4", parks: "EDD6D6", roads: "9C5566", roadsHigh: "B27180", roadsMid: "C68F9B", roadsLow: "DBB2BB", roadsPath: "E8CDD3", roadOutline: "F9F1F0", buildings: "E9CCCE", rail: "7A4351", ink: "7A4351"),
        .init(id: "sandstone", name: "Dune", background: "F1E9DB", land: "F1E9DB", landcover: "E8DCC8", water: "CDBC9C", parks: "E0D2B8", roads: "8A6E45", roadsHigh: "A0855C", roadsMid: "B59C76", roadsLow: "CBB694", roadsPath: "DBC9AC", roadOutline: "F1E9DB", buildings: "DCCBAB", rail: "6B5436", ink: "6B5436"),
        .init(id: "heatwave", name: "Ember", background: "1C0E09", land: "1C0E09", landcover: "28140C", water: "2C140C", parks: "381A10", roads: "FF5F1F", roadsHigh: "B04010", roadsMid: "493623", roadsLow: "3C2A1B", roadsPath: "59442C", roadOutline: "695235", buildings: "D2A55E", rail: "FFD78A", ink: "FFD78A"),
        .init(id: "ruby", name: "Garnet", background: "1A070F", land: "1A070F", landcover: "280C18", water: "2A0D17", parks: "351021", roads: "C0103C", roadsHigh: "780C2C", roadsMid: "463132", roadsLow: "392427", roadsPath: "553F3E", roadOutline: "654E4A", buildings: "EE8EA4", rail: "F6D7BC", ink: "F6D7BC"),
        .init(id: "sage", name: "Meadow", background: "DDE8DD", land: "DDE8DD", landcover: "D8E4DA", water: "C5D4CB", parks: "D3DFD7", roads: "3F624F", roadsHigh: "587A68", roadsMid: "92B4A2", roadsLow: "AABFB4", roadsPath: "BECCBF", roadOutline: "C8D8CC", buildings: "8BAD9B", rail: "2D4739", ink: "2D4739"),
        .init(id: "rustic", name: "Hearth", background: "DFD5C8", land: "DFD5C8", landcover: "D9CEC0", water: "C4B8A8", parks: "D2C6B7", roads: "563A2A", roadsHigh: "7A5040", roadsMid: "A68070", roadsLow: "B89080", roadsPath: "C6A898", roadOutline: "CCB0A0", buildings: "9E7A62", rail: "44362C", ink: "44362C"),
        .init(id: "midnight_blue", name: "Nocturne", background: "0A1628", land: "0A1628", landcover: "0D1C2F", water: "061020", parks: "0F2235", roads: "C99C37", roadsHigh: "8A6820", roadsMid: "333530", roadsLow: "272C2E", roadsPath: "414033", roadOutline: "4F4B36", buildings: "6E5A45", rail: "D6B352", ink: "D6B352"),
        .init(id: "neon", name: "Pulse", background: "0B0F1A", land: "0B0F1A", landcover: "130D22", water: "001433", parks: "1A0B2A", roads: "FF2D95", roadsHigh: "FF6EB4", roadsMid: "8A33FF", roadsLow: "4A0099", roadsPath: "21203A", roadOutline: "0B0F1A", buildings: "FF2D95", rail: "00F5FF", ink: "00F5FF"),
        .init(id: "terracotta", name: "Sienna", background: "F5EDE4", land: "F5EDE4", landcover: "EFE7DA", water: "A8C4C4", parks: "E8E0D0", roads: "A0522D", roadsHigh: "C07048", roadsMid: "DCA882", roadsLow: "D8B898", roadsPath: "E4C8B0", roadOutline: "EAD4C0", buildings: "D9A08A", rail: "8B4513", ink: "8B4513"),
        .init(id: "blueprint", name: "Draft", background: "1A3A5C", land: "1A3A5C", landcover: "1D4066", water: "0E2740", parks: "1F466F", roads: "D8EEFA", roadsHigh: "7AAED0", roadsMid: "435F7D", roadsLow: "375473", roadsPath: "526C88", roadOutline: "607993", buildings: "6EA4CC", rail: "E8F4FF", ink: "E8F4FF"),
        .init(id: "contrast_zones", name: "Contour", background: "FFFFFF", land: "FFFFFF", landcover: "F6F6F6", water: "B0B0B0", parks: "ECECEC", roads: "1A1A1A", roadsHigh: "484848", roadsMid: "989898", roadsLow: "B8B8B8", roadsPath: "CCCCCC", roadOutline: "D8D8D8", buildings: "6C6C6C", rail: "111111", ink: "111111"),
        .init(id: "copper_patina", name: "Verdigris", background: "E8F0F0", land: "E8F0F0", landcover: "E0ECE8", water: "C0D8D8", parks: "D8E8E0", roads: "B87333", roadsHigh: "629898", roadsMid: "A8CACA", roadsLow: "B8D4D4", roadsPath: "C8DEDE", roadOutline: "D2E6E6", buildings: "8AB6B6", rail: "2A5A5A", ink: "2A5A5A"),
        .init(id: "emerald", name: "Evergreen", background: "062C22", land: "062C22", landcover: "0B3F30", water: "0D4536", parks: "0F523E", roads: "4ADEB0", roadsHigh: "18A070", roadsMid: "32554B", roadsLow: "25493F", roadsPath: "42635A", roadOutline: "517268", buildings: "1A785B", rail: "E3F9F1", ink: "E3F9F1"),
        .init(id: "forest", name: "Grove", background: "F0F4F0", land: "F0F4F0", landcover: "E2EEE2", water: "B8D4D4", parks: "D4E8D4", roads: "3A5E4D", roadsHigh: "527A66", roadsMid: "90B4A0", roadsLow: "A8C4B4", roadsPath: "C2D4CA", roadOutline: "CEDBD2", buildings: "8AB19A", rail: "2D4A3E", ink: "2D4A3E"),
        .init(id: "japanese_ink", name: "Sumi", background: "FAF8F5", land: "FAF8F5", landcover: "F5F3EE", water: "E8E4E0", parks: "F0EDE8", roads: "8B2500", roadsHigh: "505050", roadsMid: "A8A8A8", roadsLow: "BCBAB6", roadsPath: "D0CECA", roadOutline: "DDDBD8", buildings: "959595", rail: "2C2C2C", ink: "2C2C2C"),
        .init(id: "noir", name: "Nightfall", background: "000000", land: "000000", landcover: "0E0E0E", water: "0B0B0B", parks: "171717", roads: "E8E8E8", roadsHigh: "A0A0A0", roadsMid: "333333", roadsLow: "242424", roadsPath: "454545", roadOutline: "575757", buildings: "6F6F6F", rail: "FFFFFF", ink: "FFFFFF"),
        .init(id: "ocean", name: "Tide", background: "F0F8FA", land: "F0F8FA", landcover: "E4F1F1", water: "B8D8E8", parks: "D8EAE8", roads: "14536A", roadsHigh: "2878A0", roadsMid: "7ABCD4", roadsLow: "AACCE0", roadsPath: "BCD8E8", roadOutline: "CCE4F0", buildings: "67AED0", rail: "1A5F7A", ink: "1A5F7A"),
        .init(id: "pastel_dream", name: "Reverie", background: "FAF7F2", land: "FAF7F2", landcover: "F1F2EB", water: "D4E4ED", parks: "E8EDE4", roads: "6870A0", roadsHigh: "9898B8", roadsMid: "C4C2D0", roadsLow: "CCCCDA", roadsPath: "D8D8E2", roadOutline: "E0E0E8", buildings: "CEC3CB", rail: "5D5A6D", ink: "5D5A6D")
    ]
}

extension PosterDocument {
    var locationPresentation: LocationPresentation {
        let country = location.country?.nonEmpty ?? ""
        let city = location.city?.nonEmpty ?? location.administrativeArea?.nonEmpty ?? country
        let validContinents = ["AFRICA", "ASIA", "EUROPE", "NORTH AMERICA", "SOUTH AMERICA", "OCEANIA", "ANTARCTICA"]
        let continent = location.continent?.nonEmpty.flatMap { validContinents.contains($0.uppercased()) ? $0 : nil } ?? ""

        if camera.zoom < 7 {
            guard let primary = country.nonEmpty else { return .init(primary: "", secondary: "") }
            return .init(primary: primary, secondary: distinctSecondary(continent, primary: primary))
        }
        if camera.zoom < 12 || typography.cityIsUserEdited {
            return .init(primary: city, secondary: distinctSecondary(country, primary: city))
        }

        let district = location.district?.nonEmpty ?? city
        let secondary = district.caseInsensitiveCompare(city) == .orderedSame ? distinctSecondary(country, primary: district) : distinctSecondary(city, primary: district)
        return .init(primary: district, secondary: secondary)
    }

    private func distinctSecondary(_ secondary: String, primary: String) -> String {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return secondary.compare(primary, options: options) == .orderedSame ? "" : secondary
    }

    mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        if themeID == "midnight" { themeID = "midnight_blue" }
        if themeID == "oxide" { themeID = "heatwave" }
        if !PosterTheme.all.contains(where: { $0.id == themeID }) { themeID = PosterTheme.defaultID }
        camera.latitude = camera.latitude.clamped(to: -90...90); camera.longitude = camera.longitude.clamped(to: -180...180); camera.zoom = camera.zoom.clamped(to: 0...22); camera.bearing = camera.bearing.truncatingRemainder(dividingBy: 360); if camera.bearing < 0 { camera.bearing += 360 }
    }
}

extension Comparable { func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) } }
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
