import SwiftUI

@main
struct Body3DMacApp: App {
    @StateObject private var library = ModelLibrary()
    @StateObject private var server = LocalHTTPServer()

    var body: some Scene {
        WindowGroup("关节-肌群解析") {
            rootView
                .environmentObject(library)
                .environmentObject(server)
                .task {
                    library.load()
                    server.start()
                }
        }
#if os(macOS)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
#endif
    }

    @ViewBuilder
    private var rootView: some View {
#if os(macOS)
        CatalogView()
            .frame(minWidth: 1080, minHeight: 720)
#else
        CatalogView()
#endif
    }
}
