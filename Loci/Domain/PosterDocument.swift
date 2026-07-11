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

    static let tokyo = PosterDocument(
        id: UUID(), schemaVersion: currentSchemaVersion, title: "TOKYO", updatedAt: .now,
        location: .init(latitude: 35.6762, longitude: 139.6503, resolvedName: "Tokyo, Japan", city: "TOKYO", country: "JAPAN"),
        camera: .init(latitude: 35.6762, longitude: 139.6503, zoom: 11), layout: .socialPortrait,
        themeID: PosterTheme.defaultID, layerVisibility: .all, typography: .default
    )
}

struct PosterLocation: Codable, Equatable, Sendable { var latitude: Double; var longitude: Double; var resolvedName: String?; var city: String?; var country: String? }
struct PosterCamera: Codable, Equatable, Sendable { var latitude: Double; var longitude: Double; var zoom: Double; var bearing: Double = 0 }
struct LayerVisibility: Codable, Equatable, Sendable { var water: Bool; var green: Bool; var buildings: Bool; var roads: Bool; static let all = Self(water: true, green: true, buildings: true, roads: true) }
struct PosterTypography: Codable, Equatable, Sendable { var cityVisible: Bool; var countryVisible: Bool; var subtitleVisible: Bool; var cityIsUserEdited: Bool; var countryIsUserEdited: Bool; var subtitle: String; static let `default` = Self(cityVisible: true, countryVisible: true, subtitleVisible: true, cityIsUserEdited: false, countryIsUserEdited: false, subtitle: "A PLACE TO REMEMBER") }

enum PosterLayout: String, Codable, CaseIterable, Identifiable, Sendable { case socialPortrait, posterPortrait, landscape, a4Portrait; var id: String { rawValue }
    var title: String { switch self { case .socialPortrait: "4:5"; case .posterPortrait: "2:3"; case .landscape: "3:2"; case .a4Portrait: "A4" } }
    var aspectRatio: CGFloat { switch self { case .socialPortrait: 4.0 / 5.0; case .posterPortrait: 2.0 / 3.0; case .landscape: 3.0 / 2.0; case .a4Portrait: 210.0 / 297.0 } }
    var pixelSize: CGSize { switch self { case .socialPortrait: .init(width: 1920, height: 2400); case .posterPortrait: .init(width: 2000, height: 3000); case .landscape: .init(width: 3000, height: 2000); case .a4Portrait: .init(width: 2100, height: 2970) } }
}

struct PosterTheme: Identifiable, Equatable, Sendable {
    let id: String
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

    static let defaultID = "noir"
    static let all: [Self] = [
        .init(id: "noir", background: "000000", land: "000000", landcover: "0E0E0E", water: "0B0B0B", parks: "171717", roads: "E8E8E8", roadsHigh: "A0A0A0", roadsMid: "333333", roadsLow: "242424", roadsPath: "454545", roadOutline: "575757", buildings: "6F6F6F", rail: "FFFFFF", ink: "FFFFFF"),
        .init(id: "midnight", background: "0A1628", land: "0A1628", landcover: "0D1C2F", water: "061020", parks: "0F2235", roads: "C99C37", roadsHigh: "8A6820", roadsMid: "333530", roadsLow: "272C2E", roadsPath: "414033", roadOutline: "4F4B36", buildings: "6E5A45", rail: "D6B352", ink: "D6B352"),
        .init(id: "carrara", background: "F4F1EA", land: "F4F1EA", landcover: "ECE7DD", water: "C7CDD0", parks: "E6E3D8", roads: "3A3631", roadsHigh: "565049", roadsMid: "6E675E", roadsLow: "8B8378", roadsPath: "A89F92", roadOutline: "F4F1EA", buildings: "E0DACD", rail: "2E2A26", ink: "2E2A26"),
        .init(id: "oxide", background: "1C0E09", land: "1C0E09", landcover: "28140C", water: "2C140C", parks: "381A10", roads: "FF5F1F", roadsHigh: "B04010", roadsMid: "493623", roadsLow: "3C2A1B", roadsPath: "59442C", roadOutline: "695235", buildings: "D2A55E", rail: "FFD78A", ink: "FFD78A"),
        .init(id: "sage", background: "DDE8DD", land: "DDE8DD", landcover: "D8E4DA", water: "C5D4CB", parks: "D3DFD7", roads: "3F624F", roadsHigh: "587A68", roadsMid: "92B4A2", roadsLow: "AABFB4", roadsPath: "BECCBF", roadOutline: "C8D8CC", buildings: "8BAD9B", rail: "2D4739", ink: "2D4739"),
        .init(id: "ruby", background: "1A070F", land: "1A070F", landcover: "280C18", water: "2A0D17", parks: "351021", roads: "C0103C", roadsHigh: "780C2C", roadsMid: "463132", roadsLow: "392427", roadsPath: "553F3E", roadOutline: "654E4A", buildings: "EE8EA4", rail: "F6D7BC", ink: "F6D7BC")
    ]
}

extension PosterDocument {
    mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        if !PosterTheme.all.contains(where: { $0.id == themeID }) { themeID = PosterTheme.defaultID }
        camera.latitude = camera.latitude.clamped(to: -90...90); camera.longitude = camera.longitude.clamped(to: -180...180); camera.zoom = camera.zoom.clamped(to: 0...22); camera.bearing = 0
    }
}

extension Comparable { func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) } }
