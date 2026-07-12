import CoreLocation
import SwiftUI

#if canImport(MapLibre)
import MapLibre

struct MapLibreMapView: UIViewRepresentable {
    let document: PosterDocument
    let onViewportChange: (MapViewport) -> Void
    let onViewportInteractionBegan: () -> Void
    let onViewportSettled: (MapViewport) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapServiceConfiguration.styleURL)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.setCenter(document.coordinate, zoomLevel: document.camera.zoom, direction: document.camera.bearing, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        let target = document.coordinate
        let directionDelta = abs(mapView.direction.shortestDelta(to: document.camera.bearing))
        if mapView.centerCoordinate.distance(to: target) > 0.00001 || abs(mapView.zoomLevel - document.camera.zoom) > 0.01 || directionDelta > 0.1 {
            context.coordinator.programmaticTarget = document.camera
            context.coordinator.isApplyingDocument = true
            mapView.setCenter(target, zoomLevel: document.camera.zoom, direction: document.camera.bearing, animated: false)
            context.coordinator.isApplyingDocument = false
        }
        if let style = mapView.style { MapStyleApplicator.apply(document: document, to: style) }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreMapView
        var isApplyingDocument = false
        var programmaticTarget: PosterCamera?
        var shouldReportViewportChanges: Bool { !isApplyingDocument }

        init(parent: MapLibreMapView) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MapStyleApplicator.apply(document: parent.document, to: style)
            reportViewport(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            if let viewport = viewport(mapView) {
                if let target = programmaticTarget {
                    programmaticTarget = nil
                    if viewport.camera.isApproximatelyEqual(to: target) { return }
                }
                guard shouldReportViewportChanges else { return }
                parent.onViewportSettled(viewport)
            }
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            guard shouldReportViewportChanges else { return }
            if programmaticTarget != nil { return }
            parent.onViewportInteractionBegan()
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            // Keep the last committed camera and location text stable until movement ends.
        }

        private func reportViewport(_ mapView: MLNMapView) {
            if let viewport = viewport(mapView) { parent.onViewportChange(viewport) }
        }

        private func viewport(_ mapView: MLNMapView) -> MapViewport? {
            let size = mapView.bounds.size
            guard size.width > 1, size.height > 1 else {
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    self.reportViewport(mapView)
                }
                return nil
            }
            return .init(camera: .init(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude, zoom: mapView.zoomLevel, bearing: mapView.direction.normalizedBearing), size: size)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            parent.onFailure(error.localizedDescription)
        }
    }
}

private extension PosterCamera {
    func isApproximatelyEqual(to other: PosterCamera) -> Bool {
        abs(latitude - other.latitude) < 0.00001 &&
        abs(longitude - other.longitude) < 0.00001 &&
        abs(zoom - other.zoom) < 0.01 &&
        abs(bearing.shortestDelta(to: other.bearing)) < 0.1
    }
}

struct MapLibreRenderer: MapRenderer {
    func snapshot(document: PosterDocument, size: CGSize, viewport: MapViewport) async throws -> UIImage {
        guard viewport.isValid else { throw LociError.previewUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let coordinate = CLLocationCoordinate2D(latitude: viewport.camera.latitude, longitude: viewport.camera.longitude)
                let camera = MLNMapCamera(lookingAtCenter: coordinate, altitude: 0, pitch: 0, heading: viewport.camera.bearing)
                let options = MLNMapSnapshotOptions(styleURL: MapServiceConfiguration.styleURL, camera: camera, size: viewport.size)
                options.zoomLevel = viewport.camera.zoom
                options.scale = viewport.outputScale(for: size)
                options.showsLogo = false
                options.showsAttribution = false
                let snapshotter = MLNMapSnapshotter(options: options)
                let delegate = SnapshotStyleDelegate(document: document)
                snapshotter.delegate = delegate
                do {
                    let snapshot = try await snapshotter.start()
                    withExtendedLifetime(delegate) { continuation.resume(returning: snapshot.image) }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class SnapshotStyleDelegate: NSObject, MLNMapSnapshotterDelegate, @unchecked Sendable {
    let document: PosterDocument
    init(document: PosterDocument) { self.document = document }
    func mapSnapshotter(_ snapshotter: MLNMapSnapshotter, didFinishLoading style: MLNStyle) {
        MapStyleApplicator.apply(document: document, to: style)
    }
}

enum MapStyleApplicator {
    static func apply(document: PosterDocument, to style: MLNStyle) {
        let theme = PosterTheme.all.first(where: { $0.id == document.themeID }) ?? PosterTheme.all[0]
        for layer in style.layers {
            let id = layer.identifier
            if let background = layer as? MLNBackgroundStyleLayer {
                background.backgroundColor = colorExpression(theme.background)
            } else if let fill = layer as? MLNFillStyleLayer {
                let color = fillColor(for: id, theme: theme)
                fill.fillColor = colorExpression(color)
                fill.fillOutlineColor = colorExpression(color)
            } else if let line = layer as? MLNLineStyleLayer {
                line.lineColor = colorExpression(lineColor(for: id, theme: theme))
            }

            switch id {
            case "loci-water", "loci-waterway": layer.isVisible = document.layerVisibility.water
            case "loci-landcover", "loci-park", "loci-aeroway": layer.isVisible = document.layerVisibility.green
            case "loci-building": layer.isVisible = document.layerVisibility.buildings
            case "loci-rail", "loci-road-overview-high", "loci-road-overview-mid", "loci-road-overview-low", "loci-road-major-casing", "loci-road-high-casing", "loci-road-mid-casing", "loci-road-major", "loci-road-high", "loci-road-mid", "loci-road-low": layer.isVisible = document.layerVisibility.roads
            default: break
            }
        }
    }

    private static func fillColor(for id: String, theme: PosterTheme) -> String {
        if id == "loci-water" { return theme.water }
        if id == "loci-building" { return theme.buildings }
        if id == "loci-landcover" { return theme.landcover }
        if id == "loci-park" || id == "loci-aeroway" { return theme.parks }
        return theme.land
    }

    private static func lineColor(for id: String, theme: PosterTheme) -> String {
        switch id {
        case "loci-waterway": theme.water
        case "loci-rail": theme.rail
        case "loci-road-overview-high", "loci-road-high": theme.roadsHigh
        case "loci-road-overview-mid", "loci-road-mid": theme.roadsMid
        case "loci-road-overview-low", "loci-road-low": theme.roadsLow
        case "loci-road-major": theme.roads
        case "loci-road-major-casing", "loci-road-high-casing", "loci-road-mid-casing": theme.roadOutline
        default: theme.roads
        }
    }

    private static func colorExpression(_ hex: String) -> NSExpression {
        NSExpression(forConstantValue: UIColor(hex: hex))
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDegrees {
        max(abs(latitude - other.latitude), abs(longitude - other.longitude))
    }
}

private extension CLLocationDirection {
    var normalizedBearing: CLLocationDirection {
        let value = truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    func shortestDelta(to other: CLLocationDirection) -> CLLocationDirection {
        ((normalizedBearing - other.normalizedBearing + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
}

extension PosterDocument {
    var coordinate: CLLocationCoordinate2D { .init(latitude: camera.latitude, longitude: camera.longitude) }
}
#endif
