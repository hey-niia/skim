import SwiftUI

@main
struct SkimApp: App {
    @StateObject private var sourceStore = SourceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sourceStore)
                .frame(minWidth: 860, minHeight: 560)
                .tint(Color(hex: "00A2F1"))
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
