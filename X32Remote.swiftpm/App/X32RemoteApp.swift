import SwiftUI

@main
struct X32RemoteApp: App {
    @State private var app = AppModel()

    init() {
        ConsoleFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
