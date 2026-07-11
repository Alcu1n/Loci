import Foundation

enum MapServiceConfiguration {
    static var styleURL: URL {
        guard let url = Bundle.main.url(forResource: "loci-map-style", withExtension: "json") else {
            preconditionFailure("The bundled Loci MapLibre style is missing.")
        }
        return url
    }
    static let posterSignature = "©Loci"
    static let compactMapAttribution = "© OpenStreetMap contributors · ODbL"
    static let exportAttribution = "© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap"
}
