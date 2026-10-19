import SwiftUI

/// First screen: find the X32 on the network, type its IP, or try the demo desk.
struct ConnectView: View {
    @Bindable var app: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ConnectHeader()
                    .padding(.top, 30)
                if let error = app.lastError {
                    ErrorBanner(text: error)
                }
                Panel(title: "Mixers on this network") {
                    DiscoveredList(app: app)
                }
                Panel(title: "Connect by IP address") {
                    ManualConnect(app: app)
                }
                DemoButton(app: app)
                Text("Not made by or affiliated with Behringer or Music Tribe.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .onAppear {
            app.startDiscovery()
        }
        .onDisappear {
            app.stopDiscovery()
        }
    }
}

private struct ConnectHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            AppMark()
                .frame(width: 76, height: 76)
            Text("X32 Remote")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("Mix your Behringer X32 or Midas M32 from this iPad.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.solo)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.solo.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.solo.opacity(0.4), lineWidth: 1))
    }
}

private struct DiscoveredList: View {
    let app: AppModel

    var body: some View {
        if app.discovered.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Looking for an X32…")
                        .foregroundStyle(Theme.text)
                    Text("Make sure this iPad is on the same network as the desk. If iOS asks about Local Network access, tap Allow.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(app.discovered) { console in
                    DiscoveredRow(app: app, console: console)
                }
            }
        }
    }
}

private struct DiscoveredRow: View {
    let app: AppModel
    let console: X32Discovery.Console

    var body: some View {
        Button {
            app.connect(host: console.ip)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(console.name.isEmpty ? console.model : console.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(console.model) · \(console.ip) · firmware \(console.firmware)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text("Connect")
                    .barChip(active: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        }
        .buttonStyle(.plain)
    }
}

private struct ManualConnect: View {
    let app: AppModel
    @State private var hostText = ""
    @FocusState private var hostFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("e.g. 192.168.1.50", text: $hostText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($hostFocused)
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
                    .submitLabel(.go)
                    .onSubmit {
                        app.connect(host: hostText)
                    }
                Button {
                    hostFocused = false
                    app.connect(host: hostText)
                } label: {
                    Text("Connect")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 110, height: 46)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(hostText.isEmpty)
            }
            if !app.settings.recentHosts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Recent")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                        ForEach(app.settings.recentHosts, id: \.self) { host in
                            Button {
                                hostText = host
                                app.connect(host: host)
                            } label: {
                                Text(host)
                                    .font(Theme.mono(13))
                                    .barChip()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("On the X32: press Setup, then the Network tab, to see its IP address.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.tertiary)
        }
        .onAppear {
            if hostText.isEmpty {
                hostText = app.settings.lastHost
            }
        }
    }
}

private struct DemoButton: View {
    let app: AppModel

    var body: some View {
        Button {
            app.startDemo()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                Text("Try the demo desk")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Shown while waiting for the first reply from the desk.
struct ConnectingView: View {
    let app: AppModel
    let host: String

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Connecting to \(host)…")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("If this is the first time, iOS may ask to allow Local Network access.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel") {
                app.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// The app's logo: three faders.
struct AppMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.23, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.20), Color(red: 0.07, green: 0.075, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                HStack(spacing: s * 0.13) {
                    ForEach(0..<3, id: \.self) { i in
                        AppMarkFader(size: s, position: [0.62, 0.30, 0.48][i], highlighted: i == 1)
                    }
                }
            }
            .frame(width: s, height: s)
        }
    }
}

private struct AppMarkFader: View {
    let size: CGFloat
    let position: CGFloat
    let highlighted: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.6)
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(highlighted ? Theme.accent : Color(white: 0.85))
                .frame(width: size * 0.17, height: size * 0.11)
                .offset(y: size * 0.6 * position - size * 0.055)
        }
        .frame(height: size * 0.6)
    }
}
