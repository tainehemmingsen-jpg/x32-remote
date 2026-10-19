import SwiftUI

struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()
            switch app.phase {
            case .idle:
                ConnectView(app: app)
            case .connecting(let host):
                ConnectingView(app: app, host: host)
            case .connected:
                ConnectedRoot(app: app)
            }
            if app.linkLost && app.phase == .connected {
                LinkLostBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.linkLost)
        .onAppear {
            app.applyLaunchArguments()
        }
        .onChange(of: scenePhase) { _, newPhase in
            app.scenePhaseChanged(newPhase)
        }
    }
}

private struct ConnectedRoot: View {
    @Bindable var app: AppModel

    var body: some View {
        switch app.settings.mode {
        case .mixer:
            MixerScreen(app: app)
        case .monitor:
            MonitorScreen(app: app)
        case .simple:
            SimpleScreen(app: app)
        }
    }
}

private struct LinkLostBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.black)
            Text("Lost contact with the desk — reconnecting…")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Capsule().fill(Theme.solo))
        .padding(.top, 6)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }
}
