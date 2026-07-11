import SwiftUI

struct LocationSheet: View {
    @Bindable var store: PosterEditorStore
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionLabel(title: "SEARCH")
                    MinimalTextField(title: "PLACE", placeholder: "City, landmark, or address", text: $store.searchQuery, capitalization: .words)
                        .submitLabel(.search)
                        .onSubmit { Task { await store.search() } }
                    ForEach(store.suggestions) { item in
                        Button { store.select(item) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).foregroundStyle(.white).lineLimit(2)
                                    Text([item.city, item.country].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(.gray)
                            }
                            .padding(.vertical, 13)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }

                    SectionLabel(title: "COORDINATES")
                    HStack(spacing: 18) {
                        MinimalTextField(title: "LATITUDE", placeholder: "35.6762", text: $latitude, keyboard: .numbersAndPunctuation)
                        MinimalTextField(title: "LONGITUDE", placeholder: "139.6503", text: $longitude, keyboard: .numbersAndPunctuation)
                    }
                    MinimalActionButton(title: "USE COORDINATES", icon: "scope") { store.applyCoordinates(latitude: latitude, longitude: longitude) }

                    SectionLabel(title: "CURRENT LOCATION")
                    Button { Task { await store.useCurrentLocation() } } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("USE CURRENT LOCATION").font(.system(size: 12, design: .monospaced).weight(.medium))
                            Spacer()
                            if store.isLocating { ProgressView().tint(.white) }
                        }
                        .foregroundStyle(.white).padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 52).overlay { Rectangle().stroke(Color.white.opacity(0.28), lineWidth: 1) }
                    }
                    .buttonStyle(.plain).disabled(store.isLocating)
                }
                .padding(20)
            }
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
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct TextSizeSheet: View {
    @Bindable var store: PosterEditorStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("TYPOGRAPHY").font(.system(size: 12, design: .monospaced)).foregroundStyle(.gray)
                    EditorToggleRow(title: "City", isOn: store.document.typography.cityVisible) {
                        store.document.typography.cityVisible.toggle(); store.save()
                    }
                    EditorTextField(title: "CITY", text: Binding(get: { store.document.location.city ?? "" }, set: { store.updateCity($0) }), isEnabled: store.document.typography.cityVisible)
                    EditorToggleRow(title: "Country", isOn: store.document.typography.countryVisible) {
                        store.document.typography.countryVisible.toggle(); store.save()
                    }
                    EditorTextField(title: "COUNTRY", text: Binding(get: { store.document.location.country ?? "" }, set: { store.updateCountry($0) }), isEnabled: store.document.typography.countryVisible)
                    EditorToggleRow(title: "Subtitle", isOn: store.document.typography.subtitleVisible) {
                        store.document.typography.subtitleVisible.toggle(); store.save()
                    }
                    EditorTextField(title: "SUBTITLE", text: $store.document.typography.subtitle, isEnabled: store.document.typography.subtitleVisible)
                        .onChange(of: store.document.typography.subtitle) { _, _ in store.save() }

                    Text("FORMAT").font(.system(size: 12, design: .monospaced)).foregroundStyle(.gray)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                        ForEach(PosterLayout.allCases) { layout in
                            Button { store.setLayout(layout) } label: {
                                Text(layout.title)
                                    .font(.system(size: 12, design: .monospaced).weight(.medium))
                                    .foregroundStyle(layout == store.document.layout ? Color.black : Color.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(layout == store.document.layout ? Color.white : Color.black)
                                    .overlay { Rectangle().stroke(Color.white.opacity(layout == store.document.layout ? 1 : 0.22), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Text & Size")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { store.activeSheet = nil } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SectionLabel: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 12, design: .monospaced)).foregroundStyle(.gray) }
}

private struct MinimalTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var capitalization: TextInputAutocapitalization = .never
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(capitalization).keyboardType(keyboard)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }
    }
}

private struct MinimalActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: icon); Text(title).font(.system(size: 12, design: .monospaced).weight(.medium)); Spacer(); Image(systemName: "arrow.right") }
                .foregroundStyle(.white).padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 52).overlay { Rectangle().stroke(Color.white.opacity(0.28), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

private struct EditorToggleRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isOn ? .white : .gray)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.characters)
        }
        .padding(.vertical, 10)
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }
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
