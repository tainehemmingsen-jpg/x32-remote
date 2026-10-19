import SwiftUI

@main
struct X32RemoteApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
