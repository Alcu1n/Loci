import Foundation
import MapKit
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

struct ApplePlaceSearchClient: GeocodingClient {
    func search(query: String) async throws -> [PlaceSuggestion] {
        guard query.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let coordinate = item.placemark.location?.coordinate else { return nil }
            let city = item.placemark.locality ?? item.name ?? "Location"
            let country = item.placemark.country ?? item.placemark.administrativeArea ?? ""
            return PlaceSuggestion(
                name: item.name ?? [city, country].filter { !$0.isEmpty }.joined(separator: ", "),
                city: city,
                country: country,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                zoom: 12
            )
        }
    }
}

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
            if document.typography.cityVisible { draw(document.location.city ?? document.title, font: .monospacedSystemFont(ofSize: output.width * 0.105, weight: .bold), color: color, rect: .init(x: margin, y: output.height * 0.65, width: output.width - margin * 2, height: output.height * 0.10), alignment: .center, kern: output.width * 0.006) }
            if document.typography.countryVisible { draw(document.location.country ?? "", font: .monospacedSystemFont(ofSize: output.width * 0.030, weight: .medium), color: color.withAlphaComponent(0.74), rect: .init(x: margin, y: output.height * 0.75, width: output.width - margin * 2, height: output.height * 0.04), alignment: .center, kern: output.width * 0.004) }
            context.cgContext.setFillColor(color.withAlphaComponent(0.55).cgColor); context.cgContext.fill(.init(x: output.width * 0.44, y: output.height * 0.80, width: output.width * 0.12, height: max(1, output.width * 0.001)))
            if document.typography.subtitleVisible { draw(document.typography.subtitle.uppercased(), font: .monospacedSystemFont(ofSize: output.width * 0.020, weight: .regular), color: color.withAlphaComponent(0.64), rect: .init(x: margin, y: output.height * 0.83, width: output.width - margin * 2, height: output.height * 0.03), alignment: .center, kern: output.width * 0.002) }
            draw(String(format: "%.4f°  %.4f°", document.camera.latitude, document.camera.longitude), font: .monospacedSystemFont(ofSize: output.width * 0.013, weight: .regular), color: color.withAlphaComponent(0.48), rect: .init(x: margin, y: output.height * 0.87, width: output.width - margin * 2, height: output.height * 0.025), alignment: .center)
            draw(MapServiceConfiguration.exportAttribution, font: .monospacedSystemFont(ofSize: output.width * 0.009, weight: .regular), color: color.withAlphaComponent(0.42), rect: .init(x: margin, y: output.height * 0.93, width: output.width - margin * 2, height: output.height * 0.02), alignment: .center)
        }
    }

    private func draw(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern])
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
