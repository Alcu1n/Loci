import SwiftUI

struct EditorView: View {
    @Bindable var store: PosterEditorStore
    @State private var sharePresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbar
                PosterPreview(document: store.document, onViewportChange: store.updateViewport, onFailure: { store.errorMessage = $0 })
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .frame(maxHeight: .infinity)
                editorBar
                    .safeAreaPadding(.bottom)
                    .background(Color.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .sheet(item: $store.activeSheet) { sheet in sheetView(sheet) }
            .sheet(isPresented: $sharePresented) { if let url = store.exportedURL { ShareSheet(items: [url]) } }
            .alert("Loci", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
            .onChange(of: store.exportedURL) { _, url in sharePresented = url != nil }
        }
        .tint(.white)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
    }

    private var toolbar: some View { ZStack { HStack { Button("New", systemImage: "plus") { store.newPoster() }.labelStyle(.iconOnly).accessibilityLabel("New poster"); Spacer(); Button { Task { await store.export() } } label: { if store.isExporting { ProgressView().tint(.white) } else { Image(systemName: "square.and.arrow.up") } }.disabled(store.isExporting || store.previewViewport == nil).accessibilityLabel("Export PNG") }.padding(.horizontal, 20).frame(height: 56).frame(maxHeight: .infinity, alignment: .top); Text(store.document.title).font(.system(size: 10, design: .monospaced).weight(.bold)).lineLimit(1).minimumScaleFactor(0.7).accessibilityLabel("\(store.document.title), map poster").frame(maxHeight: .infinity, alignment: .bottom).padding(.horizontal, 80).padding(.bottom, 7) }.frame(height: 64).background(Color.black).overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.18)) } }
    private var editorBar: some View { HStack(spacing: 0) { editorButton("Location", icon: "location") { store.activeSheet = .location }; editorButton("Style", icon: "circle.lefthalf.filled") { store.activeSheet = .style }; editorButton("Text & Size", icon: "textformat.size") { store.activeSheet = .text } }.frame(height: 76).overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.18)) } }
    private func editorButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 7) { Image(systemName: icon); Text(title).font(.system(size: 11, design: .monospaced)) }.frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.plain).overlay(alignment: .trailing) { Divider().overlay(Color.white.opacity(0.12)) } .accessibilityLabel(title) }
    @ViewBuilder private func sheetView(_ sheet: PosterEditorStore.Sheet) -> some View { switch sheet { case .location: LocationSheet(store: store); case .style: StyleSheet(store: store); case .text: TextSizeSheet(store: store); case .settings: SettingsView() } }
}

private struct PosterPreview: View {
    let document: PosterDocument
    let onViewportChange: (MapViewport) -> Void
    let onFailure: (String) -> Void
    var body: some View { GeometryReader { proxy in let width = proxy.size.width; let height = min(proxy.size.height, width / document.layout.aspectRatio); PosterArtwork(document: document, onViewportChange: onViewportChange, onFailure: onFailure).frame(width: width, height: height).frame(maxHeight: .infinity, alignment: .center) }.aspectRatio(document.layout.aspectRatio, contentMode: .fit).accessibilityLabel("Poster preview for \(document.location.city ?? document.title)") }
}

struct PosterArtwork: View {
    let document: PosterDocument
    let onViewportChange: (MapViewport) -> Void
    let onFailure: (String) -> Void
    private var theme: PosterTheme { PosterTheme.all.first(where: { $0.id == document.themeID }) ?? PosterTheme.all[0] }
    var body: some View { GeometryReader { proxy in ZStack(alignment: .bottom) { MapLibreMapView(document: document, onViewportChange: onViewportChange, onFailure: onFailure).overlay(alignment: .top) { LinearGradient(colors: [Color(hex: theme.background).opacity(Double(PosterFade.opacity)), .clear], startPoint: .top, endPoint: .bottom).frame(height: proxy.size.height * PosterFade.topFraction).allowsHitTesting(false) }.overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Color(hex: theme.background).opacity(Double(PosterFade.opacity))], startPoint: .top, endPoint: .bottom).frame(height: proxy.size.height * PosterFade.bottomFraction).allowsHitTesting(false) }; VStack(spacing: 6) { if document.typography.cityVisible { Text(document.location.city ?? document.title).font(.system(size: max(28, proxy.size.width * 0.105), weight: .bold, design: .monospaced)).tracking(proxy.size.width * 0.006).lineLimit(1).minimumScaleFactor(0.45) }; if document.typography.countryVisible { Text(document.location.country ?? "").font(.system(size: max(10, proxy.size.width * 0.030), weight: .medium, design: .monospaced)).tracking(proxy.size.width * 0.004).foregroundStyle(Color(hex: theme.ink).opacity(0.72)) }; Rectangle().fill(Color(hex: theme.ink).opacity(0.55)).frame(width: proxy.size.width * 0.12, height: 1).padding(.vertical, 4); if document.typography.subtitleVisible { Text(document.typography.subtitle.uppercased()).font(.system(size: max(8, proxy.size.width * 0.020), design: .monospaced)).tracking(proxy.size.width * 0.002).foregroundStyle(Color(hex: theme.ink).opacity(0.64)) }; Text(String(format: "%.4f°  %.4f°", document.camera.latitude, document.camera.longitude)).font(.system(size: max(7, proxy.size.width * 0.013), design: .monospaced)).foregroundStyle(Color(hex: theme.ink).opacity(0.48)); Text(MapServiceConfiguration.exportAttribution).font(.system(size: max(6, proxy.size.width * 0.009), design: .monospaced)).foregroundStyle(Color(hex: theme.ink).opacity(0.42)).padding(.top, 3) }.multilineTextAlignment(.center).foregroundStyle(Color(hex: theme.ink)).frame(maxWidth: .infinity).padding(.horizontal, proxy.size.width * 0.08).padding(.bottom, proxy.size.height * 0.07).allowsHitTesting(false) } }.background(Color(hex: theme.background)).clipShape(.rect) }
}

extension Color { init(hex: String) { self.init(uiColor: UIColor(hex: hex)) } }
