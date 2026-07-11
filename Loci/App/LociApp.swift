import SwiftUI

@main
struct LociApp: App {
    @State private var store = PosterEditorStore.live()

    var body: some Scene {
        WindowGroup {
            EditorView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}
