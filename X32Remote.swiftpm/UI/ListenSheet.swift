import SwiftUI

/// "Listen": the desk's solo bus in this iPad's earphones. Solo anything on the desk or in the
/// app and hear it wherever you're standing.
struct ListenSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRouting = false
    @State private var manualIP = ""

    var body: some View {
        let listen = app.listen
        NavigationStack {
            Form {
                // The big switch, with what's happening.
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: listen.running ? "headphones.circle.fill" : "headphones.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(listen.running ? (listen.receiving ? Theme.on : Theme.solo) : Theme.secondary)
                            .symbolEffect(.pulse, isActive: listen.running && !listen.receiving)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(listen.running ? "Listening" : "Off")
                                .font(.system(size: 20, weight: .bold))
                            Text(listen.running ? listen.status : "Solo something and hear it in the earphones plugged into this iPad.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("Listen", isOn: Binding(get: { listen.running }, set: { on in
                            on ? listen.start() : listen.stop()
                        }))
                        .labelsHidden()
                        .tint(Theme.on)
                    }
                    .padding(.vertical, 4)
                    if let problem = listen.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.solo)
                    }
                    if listen.running {
                        HStack {
                            Label("About \(listen.delayMS) ms behind", systemImage: "clock")
                            Spacer()
                            if listen.source == .mac {
                                Text(listen.dropouts == 0 ? "No dropouts" : "\(listen.dropouts) dropouts")
                                    .foregroundStyle(listen.dropouts == 0 ? Theme.secondary : Theme.solo)
                            }
                        }
                        .font(.system(size: 13))
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill").foregroundStyle(Theme.secondary)
                        Slider(value: Binding(get: { Double(listen.volume) }, set: { listen.volume = Float($0) }), in: 0...1)
                            .tint(Theme.accent)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.secondary)
                    }
                    ClearSoloButton(app: app, height: 40)
                } header: {
                    Text("Volume")
                } footer: {
                    Text("Nothing soloed? You hear whatever the desk's monitor is set to (usually the main mix). The desk's Solo/phones level also changes this.")
                }

                // Where the audio comes from.
                Section {
                    Picker("From", selection: Binding(get: { listen.source }, set: { listen.source = $0 })) {
                        ForEach(ListenEngine.Source.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if listen.source == .mac {
                        macRows(listen)
                    } else {
                        Text("Plug the iPad into the USB port on the back of the X32 (its USB card) with a USB-C cable. Your earphones then need the iPad's headphone socket, or a USB-C hub with a headphone adapter: the app won't play back into the desk.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                } header: {
                    Text("Audio from")
                }

                // The desk side: solo onto two USB channels.
                Section {
                    Picker("Use outputs", selection: Binding(get: { app.listenPlan.output }, set: { app.listenPlan = ListenRouting.Plan(output: $0) })) {
                        ForEach(ListenRouting.Plan.choices, id: \.output) { p in
                            Text("Out \(p.output)/\(p.output + 1) → USB \(p.usbLeft)/\(p.usbRight)").tag(p.output)
                        }
                    }
                    if app.listenRoutingReady {
                        Label("Solo goes to USB \(app.listenPlan.usbLeft)/\(app.listenPlan.usbRight)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.on)
                    } else {
                        Button {
                            confirmRouting = true
                        } label: {
                            Label("Send solo to USB \(app.listenPlan.usbLeft)/\(app.listenPlan.usbRight)…", systemImage: "arrow.triangle.branch")
                        }
                    }
                } header: {
                    Text("On the desk")
                } footer: {
                    Text("The desk only sends audio out of its USB card, so the solo bus goes to two local outputs and those go to the card. Pick a pair you don't use for speakers.")
                }

                if listen.source == .mac {
                    Section {
                        Picker("Delay vs. dropouts", selection: Binding(get: { listen.cushion }, set: { listen.cushion = $0 })) {
                            ForEach(ListenEngine.Cushion.allCases) { c in
                                Text("\(c.title) (\(c.rawValue) ms)").tag(c)
                            }
                        }
                    } footer: {
                        Text("If it crackles, choose Safe. On a good network Tight works and is closest to live.")
                    }
                }
            }
            .navigationTitle("Listen on this iPad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                app.loadListen()
                if listen.source == .mac { listen.search() }
                manualIP = listen.bridgeIP
            }
            .confirmationDialog("Send solo to USB \(app.listenPlan.usbLeft)/\(app.listenPlan.usbRight)?",
                                isPresented: $confirmRouting, titleVisibility: .visible) {
                Button("Change the routing") { app.setUpListenRouting() }
            } message: {
                let replaces = app.listenRoutingReplaces()
                Text("Outputs \(app.listenPlan.output) and \(app.listenPlan.output + 1) will carry the solo bus, and they'll go to the USB card."
                     + (replaces.isEmpty ? "" : " This replaces: " + replaces.joined(separator: "; ") + ".")
                     + " Undo puts it back.")
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func macRows(_ listen: ListenEngine) -> some View {
        if listen.bridges.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking for X32 Listen Bridge on this network…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        ForEach(listen.bridges) { b in
            Button {
                listen.bridgeIP = b.ip
                manualIP = b.ip
            } label: {
                HStack {
                    Image(systemName: "laptopcomputer")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).foregroundStyle(Theme.text)
                        Text(b.ip).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if listen.bridgeIP == b.ip {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        HStack {
            TextField("Mac's IP address", text: $manualIP)
                .keyboardType(.decimalPad)
                .onSubmit { useManual(listen) }
            Button("Use") { useManual(listen) }
                .disabled(IPv4.normalized(manualIP) == nil)
            Button {
                listen.search()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Search again")
        }
        Text("On the Mac plugged into the desk's USB port, run X32 Listen Bridge (in the Mac folder of this project). It shows up here by itself.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.tertiary)
    }

    private func useManual(_ listen: ListenEngine) {
        if let ip = IPv4.normalized(manualIP) {
            listen.bridgeIP = ip
            if listen.running {
                listen.stop()
                listen.start()
            }
        }
    }
}
