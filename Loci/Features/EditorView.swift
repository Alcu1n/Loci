import SwiftUI

struct EditorView: View {
    @Bindable var store: PosterEditorStore

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    toolbar(topInset: proxy.safeAreaInsets.top)
                    PosterPreview(document: store.document, onViewportChange: store.updateViewport, onViewportSettled: store.settleViewport, onFailure: { store.errorMessage = $0 })
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .frame(maxHeight: .infinity)
                    editorBar(bottomInset: proxy.safeAreaInsets.bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
            }
            .background(Color.black.ignoresSafeArea())
            .sheet(item: $store.activeSheet) { sheet in sheetView(sheet) }
            .alert("Loci", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
            .alert("Saved", isPresented: Binding(get: { store.confirmationMessage != nil }, set: { if !$0 { store.confirmationMessage = nil } })) { Button("OK", role: .cancel) { store.confirmationMessage = nil } } message: { Text(store.confirmationMessage ?? "") }
        }
        .tint(.white)
        .buttonStyle(.mediumHaptic)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
    }

    private func toolbar(topInset: CGFloat) -> some View {
        HStack(spacing: 16) {
            Button("New", systemImage: "plus") { store.newPoster() }
                .labelStyle(.iconOnly)
                .accessibilityLabel("New poster")
            Spacer()
            Text(store.document.title)
                .font(.system(size: 12, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("\(store.document.title), map poster")
            Spacer()
            Button { Task { await store.exportToPhotos() } } label: {
                if store.isExporting { ProgressView().tint(.white) } else { Image("downloadicon").resizable().scaledToFit().frame(width: 24, height: 24) }
            }
            .disabled(store.isExporting || store.previewViewport == nil)
            .accessibilityLabel("Save poster to Photos")
        }
        .padding(.top, topInset)
        .padding(.horizontal, 20)
        .frame(height: topInset + 56)
        .background(Color.black)
        .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.18)) }
    }

    private func editorBar(bottomInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            editorButton("Location", asset: "location") { store.activeSheet = .location }
                .padding(.bottom, bottomInset)
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1)
            editorButton("Style", systemIcon: "circle.lefthalf.filled") { store.activeSheet = .style }
                .padding(.bottom, bottomInset)
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1)
            editorButton("Text & Size", systemIcon: "textformat.size") { store.activeSheet = .text }
                .padding(.bottom, bottomInset)
        }
        .frame(height: 52 + bottomInset)
        .background(Color.black)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.18)) }
    }

    private func editorButton(_ title: String, systemIcon: String? = nil, asset: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let asset {
                    Image(asset).resizable().scaledToFit().frame(width: 24, height: 24)
                } else if let systemIcon {
                    Image(systemName: systemIcon).font(.system(size: 21, weight: .regular))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(title)
    }
    @ViewBuilder private func sheetView(_ sheet: PosterEditorStore.Sheet) -> some View { switch sheet { case .location: LocationSheet(store: store); case .style: StyleSheet(store: store); case .text: TextSizeSheet(store: store); case .settings: SettingsView() } }
}

private struct PosterPreview: View {
    let document: PosterDocument
    let onViewportChange: (MapViewport) -> Void
    let onViewportSettled: (MapViewport) -> Void
    let onFailure: (String) -> Void
    var body: some View { GeometryReader { proxy in let width = proxy.size.width; let height = min(proxy.size.height, width / document.layout.aspectRatio); PosterArtwork(document: document, onViewportChange: onViewportChange, onViewportSettled: onViewportSettled, onFailure: onFailure).frame(width: width, height: height).frame(maxHeight: .infinity, alignment: .center) }.aspectRatio(document.layout.aspectRatio, contentMode: .fit).accessibilityLabel("Poster preview for \(document.locationPresentation.primary)") }
}

struct PosterArtwork: View {
    let document: PosterDocument
    let onViewportChange: (MapViewport) -> Void
    let onViewportSettled: (MapViewport) -> Void
    let onFailure: (String) -> Void
    private var theme: PosterTheme { PosterTheme.all.first(where: { $0.id == document.themeID }) ?? PosterTheme.all[0] }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MapLibreMapView(document: document, onViewportChange: onViewportChange, onViewportSettled: onViewportSettled, onFailure: onFailure)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Color(hex: theme.background).opacity(Double(PosterFade.opacity)), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: proxy.size.height * PosterFade.topFraction).allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, Color(hex: theme.background).opacity(Double(PosterFade.opacity))], startPoint: .top, endPoint: .bottom)
                            .frame(height: proxy.size.height * PosterFade.bottomFraction).allowsHitTesting(false)
                    }
                posterText(width: proxy.size.width)
                    .padding(.bottom, proxy.size.height * PosterTypographyLayout.contentBottomFraction)
                posterFooter(width: proxy.size.width)
            }
        }
        .background(Color(hex: theme.background))
        .clipShape(.rect)
    }

    private func posterText(width: CGFloat) -> some View {
        let locationText = document.locationPresentation
        return VStack(spacing: 6) {
            if document.typography.cityVisible {
                Text(locationText.primary).font(.system(size: max(28, width * 0.105), weight: .bold, design: .monospaced)).tracking(width * 0.006).lineLimit(1).minimumScaleFactor(0.45)
                    .contentTransition(.opacity).animation(.easeOut(duration: 0.15), value: locationText.primary)
            }
            if document.typography.countryVisible {
                Text(locationText.secondary).font(.system(size: max(10, width * 0.030), weight: .medium, design: .monospaced)).tracking(width * 0.004).foregroundStyle(Color(hex: theme.ink).opacity(0.72))
                    .contentTransition(.opacity).animation(.easeOut(duration: 0.15), value: locationText.secondary)
            }
            LinearGradient(colors: [.clear, Color(hex: theme.ink).opacity(0.55), Color(hex: theme.ink).opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * PosterTypographyLayout.separatorWidthFraction, height: 1).padding(.vertical, 4)
            if document.typography.subtitleVisible {
                Text(document.typography.subtitle.uppercased()).font(.system(size: max(8, width * 0.020), design: .monospaced)).tracking(width * 0.002).foregroundStyle(Color(hex: theme.ink).opacity(0.64))
            }
            Text(String(format: "%.4f°  %.4f°", document.camera.latitude, document.camera.longitude)).font(.system(size: max(7, width * 0.013), design: .monospaced)).foregroundStyle(Color(hex: theme.ink).opacity(0.48))
        }
        .multilineTextAlignment(.center).foregroundStyle(Color(hex: theme.ink)).frame(maxWidth: .infinity).padding(.horizontal, width * 0.08).allowsHitTesting(false)
    }

    private func posterFooter(width: CGFloat) -> some View {
        HStack(alignment: .bottom) {
            Text(MapServiceConfiguration.compactMapAttribution).font(.system(size: max(4, width * 0.007), design: .monospaced)).foregroundStyle(Color(hex: theme.ink).opacity(0.28))
            Spacer(minLength: 8)
            Text(MapServiceConfiguration.posterSignature).font(.system(size: max(6, width * 0.009), weight: .medium)).foregroundStyle(Color(hex: theme.ink).opacity(0.52))
        }
        .padding(.horizontal, width * 0.025).padding(.bottom, width * 0.025).allowsHitTesting(false)
    }
}

extension Color { init(hex: String) { self.init(uiColor: UIColor(hex: hex)) } }

struct MediumHapticButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == MediumHapticButtonStyle {
    static var mediumHaptic: MediumHapticButtonStyle { MediumHapticButtonStyle() }
}
