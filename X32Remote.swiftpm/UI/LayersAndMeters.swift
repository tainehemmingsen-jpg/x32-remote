import SwiftUI

/// Pick which strips go on a custom layer, and its name.
struct UserLayerEditor: View {
    let app: AppModel
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<StripID> = []
    @State private var loaded = false

    private static let limit = 24

    private var groups: [(String, [StripID])] {
        [
            ("Channels", StripID.all(.channel)),
            ("Aux in", StripID.all(.auxIn)),
            ("FX returns", StripID.all(.fxReturn)),
            ("Mix buses", StripID.all(.bus)),
            ("Matrix", StripID.all(.matrix)),
            ("Main", [StripID.mainLR, StripID.monoC]),
            ("DCA", StripID.all(.dca))
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("Layer name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Text("\(selected.count) of \(UserLayerEditor.limit) chosen. They appear in desk order.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                    if !selected.isEmpty {
                        Button("Clear all", role: .destructive) {
                            selected.removeAll()
                        }
                    }
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { strip in
                            row(strip)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit \(app.layerTitle(index == 0 ? .user1 : .user2))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let layer: MixerLayer = index == 0 ? .user1 : .user2
            name = app.layerTitle(layer)
            selected = Set(app.strips(for: layer))
        }
    }

    private func row(_ strip: StripID) -> some View {
        let isOn = selected.contains(strip)
        let stripName = app.param(strip.namePath).string
        let style = ScribbleStyle(colorIndex: app.param(strip.colorPath).int)
        return Button {
            if isOn {
                selected.remove(strip)
            } else if selected.count < UserLayerEditor.limit {
                selected.insert(strip)
            }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(style.fill)
                    .frame(width: 8, height: 28)
                Text(strip.footLabel)
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 64, alignment: .leading)
                Text(stripName.isEmpty ? "—" : stripName)
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Theme.on : Theme.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let ordered = StripID.everything.filter { selected.contains($0) }
        app.setUserLayer(index, strips: ordered)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        app.setUserLayerName(index, trimmed.isEmpty ? "User \(index + 1)" : trimmed)
        let layer: MixerLayer = index == 0 ? .user1 : .user2
        if !ordered.isEmpty {
            app.selectLayer(layer)
        }
    }
}

/// Every meter on the desk at once.
struct MeterBridge: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MeterGroup(app: app, title: "Channels", strips: StripID.all(.channel))
                    MeterGroup(app: app, title: "Aux in and FX returns", strips: StripID.all(.auxIn) + StripID.all(.fxReturn))
                    MeterGroup(app: app, title: "Mix buses", strips: StripID.all(.bus))
                    MeterGroup(app: app, title: "Matrix and main", strips: StripID.all(.matrix) + [StripID.mainLR])
                }
                .padding(14)
            }
            .background(Theme.background)
            .navigationTitle("Meters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MeterGroup: View {
    let app: AppModel
    let title: String
    let strips: [StripID]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 3)], spacing: 6) {
                ForEach(strips) { strip in
                    MeterCell(app: app, strip: strip)
                }
            }
        }
    }
}

private struct MeterCell: View {
    let app: AppModel
    let strip: StripID

    var body: some View {
        let name = app.param(strip.namePath).string
        let style = ScribbleStyle(colorIndex: app.param(strip.colorPath).int)
        let muted = app.param(strip.onPath).int(or: 1) == 0
        VStack(spacing: 3) {
            MeterView(meter: app.meters.meter(strip), stereo: strip.kind == .main)
                .frame(width: strip.kind == .main ? 16 : 10, height: 170)
                .opacity(muted ? 0.4 : 1)
            Text(name.isEmpty ? strip.footLabel : name)
                .font(.system(size: 9))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(style.text)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 2).fill(style.fill))
            Text(muted ? "MUTE" : strip.footLabel)
                .font(.system(size: 8))
                .foregroundStyle(muted ? Theme.mute : Theme.tertiary)
        }
        .padding(3)
        .background(Theme.panel)
        .onTapGesture {
            app.pendingDetail = strip
            app.sheet = nil
        }
    }
}
