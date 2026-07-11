import SwiftUI

struct LocationSheet: View {
    @Bindable var store: PosterEditorStore
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Search cities, landmarks, or addresses", text: $store.searchQuery)
                        .textInputAutocapitalization(.words)
                        .onSubmit { Task { await store.search() } }
                    ForEach(store.suggestions) { item in
                        Button(item.name) { store.select(item) }
                    }
                }
                Section("Coordinates") {
                    TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
                    Button("Use coordinates") { store.applyCoordinates(latitude: latitude, longitude: longitude) }
                }
                Section {
                    Button { Task { await store.useCurrentLocation() } } label: {
                        HStack { Text("Use current location"); Spacer(); if store.isLocating { ProgressView().tint(.white) } }
                    }.disabled(store.isLocating)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Location")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { store.activeSheet = nil } } }
        }
        .preferredColorScheme(.dark)
    }
}

struct StyleSheet: View {
    @Bindable var store: PosterEditorStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("POSTER THEMES").font(.system(size: 12, design: .monospaced)).foregroundStyle(.gray)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                        ForEach(PosterTheme.all) { theme in
                            Button { store.selectTheme(theme) } label: {
                                Rectangle().fill(Color(hex: theme.background))
                                    .overlay(alignment: .bottomLeading) { Text(theme.id.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(hex: theme.ink)).padding(10) }
                                    .overlay { if theme.id == store.document.themeID { Rectangle().stroke(.white, lineWidth: 2) } }
                                    .aspectRatio(1.5, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("LAYERS").font(.system(size: 12, design: .monospaced)).foregroundStyle(.gray)
                    LayerToggle(title: "Water", isOn: store.document.layerVisibility.water) { store.toggleLayer(\.water) }
                    LayerToggle(title: "Green", isOn: store.document.layerVisibility.green) { store.toggleLayer(\.green) }
                    LayerToggle(title: "Buildings", isOn: store.document.layerVisibility.buildings) { store.toggleLayer(\.buildings) }
                    LayerToggle(title: "Roads", isOn: store.document.layerVisibility.roads) { store.toggleLayer(\.roads) }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Style")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { store.activeSheet = nil } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LayerToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(isOn ? "ON" : "OFF").font(.system(size: 12, design: .monospaced)).foregroundStyle(isOn ? .white : .gray)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.15)) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct TextSizeSheet: View {
    @Bindable var store: PosterEditorStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Typography") {
                    Toggle("Show city", isOn: $store.document.typography.cityVisible)
                    TextField("City", text: Binding(get: { store.document.location.city ?? "" }, set: { store.updateCity($0) }))
                    Toggle("Show country", isOn: $store.document.typography.countryVisible)
                    TextField("Country", text: Binding(get: { store.document.location.country ?? "" }, set: { store.updateCountry($0) }))
                    Toggle("Show subtitle", isOn: $store.document.typography.subtitleVisible)
                    TextField("Subtitle", text: $store.document.typography.subtitle)
                        .onChange(of: store.document.typography.subtitle) { _, _ in store.save() }
                }
                Section("Format") {
                    ForEach(PosterLayout.allCases) { layout in
                        Button { store.setLayout(layout) } label: {
                            HStack { Text(layout.title); Spacer(); if layout == store.document.layout { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Text & Size")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { store.activeSheet = nil } } }
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Attribution") { Text("© OpenStreetMap contributors · © OpenMapTiles · OpenFreeMap. Place search is provided by Apple MapKit.") }
                Section("Privacy") { Text("Loci stores the latest poster on this device. It does not use accounts, analytics, advertising, or background location.") }
            }
            .navigationTitle("Loci")
        }
        .preferredColorScheme(.dark)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
