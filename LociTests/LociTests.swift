import XCTest
@testable import Loci

final class LociTests: XCTestCase {
    func testUnknownThemeFallsBackToNoir() {
        var document = PosterDocument.tokyo
        document.themeID = "removed-theme"
        document.normalize()
        XCTAssertEqual(document.themeID, PosterTheme.defaultID)
    }

    func testCameraIsClampedAndNorthUp() {
        var document = PosterDocument.tokyo
        document.camera = .init(latitude: 100, longitude: -200, zoom: 50, bearing: 32)
        document.normalize()
        XCTAssertEqual(document.camera.latitude, 90)
        XCTAssertEqual(document.camera.longitude, -180)
        XCTAssertEqual(document.camera.zoom, 22)
        XCTAssertEqual(document.camera.bearing, 0)
    }

    func testAllPresetSizesStayInsideBudget() {
        for layout in PosterLayout.allCases {
            XCTAssertLessThanOrEqual(layout.pixelSize.width * layout.pixelSize.height, 12_000_000)
        }
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
        XCTAssertTrue(MapServiceConfiguration.exportAttribution.contains("OPENSTREETMAP"))
        XCTAssertTrue(MapServiceConfiguration.exportAttribution.contains("OPENMAPTILES"))
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
}
