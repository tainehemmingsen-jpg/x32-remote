import SwiftUI

/// "Build a scene": describe the gig in a sentence, check what the app came up with, and put it
/// on the desk in one go (channel names, colours, starting EQ/gate/compressor, DCAs, mixes).
struct SceneBuilderSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var plan: ScenePlan?
    @State private var thinking = false
    @State private var useAI = SceneAI.isAvailable
    @State private var message: String?
    @State private var clearRest = true
    @State private var confirming = false
    @FocusState private var typing: Bool

    private let examples = [
        "Rock band: 2 vox, 2 guitars, bass, keys, drums, with wedges",
        "Church service: pastor lapel, worship leader, 2 BVs, acoustic, keys, bass, drums, playback",
        "Conference: lectern, 2 handhelds, lapel, playback",
        "Spin class: instructor headset and music",
        "Acoustic duo: vocal, acoustic guitar, cajon, backing vocal",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on? e.g. covers band with 2 singers, sax and a DJ", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($typing)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(examples, id: \.self) { e in
                                Button {
                                    text = e
                                } label: {
                                    Text(e)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(Capsule().fill(Theme.raised2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if SceneAI.isAvailable {
                        Toggle(isOn: $useAI) {
                            Label("Use Apple Intelligence (on this iPad)", systemImage: "apple.intelligence")
                        }
                    }
                    Button {
                        build()
                    } label: {
                        HStack {
                            if thinking { ProgressView().padding(.trailing, 4) }
                            Text(plan == nil ? "Build" : "Build again")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                } header: {
                    Text("Describe the gig")
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(Theme.mute)
                    } else {
                        Text("List the instruments and mics (\"2 vox, acoustic, bass, drums\"), or just say what the event is (\"church service\", \"spin class\"). Add \"wedges\" or \"in-ears\" for monitor mixes.")
                    }
                }

                if let binding = Binding($plan) {
                    PlanEditor(plan: binding)
                    Section {
                        Toggle("Clear the names on channels it doesn't use", isOn: $clearRest)
                    } footer: {
                        Text("Sets names, colours, low cut, gate, EQ and compressor on channels 1–\(plan?.inputs.count ?? 0), names the DCAs and monitor mixes, and puts each channel on its DCA. Gain, faders, sends and routing aren't touched. It's one step: Undo puts everything back.")
                    }
                }
            }
            .navigationTitle("Build a scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.applyingPlan ? "Applying…" : "Put on desk") { confirming = true }
                        .disabled(plan?.inputs.isEmpty ?? true || app.applyingPlan)
                }
            }
            .confirmationDialog("Put “\(plan?.title ?? "")” on the desk?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Put on desk") {
                    if let plan {
                        app.applyPlan(plan, clearRest: clearRest)
                        dismiss()
                    }
                }
            } message: {
                Text("Changes channel names, colours and processing straight away. Undo takes it all back.")
            }
            .onAppear { typing = true }
        }
        .preferredColorScheme(.dark)
    }

    private func build() {
        typing = false
        message = nil
        let description = text
        if useAI && SceneAI.isAvailable {
            thinking = true
            Task {
                do {
                    let result = try await SceneAI.plan(from: description)
                    await MainActor.run {
                        thinking = false
                        plan = result ?? SceneBuilder.plan(from: description)
                        if plan == nil { message = "Couldn't work out any inputs from that. Try listing them." }
                    }
                } catch {
                    await MainActor.run {
                        thinking = false
                        // Fall back to the built-in reader.
                        plan = SceneBuilder.plan(from: description)
                        message = plan == nil ? "Couldn't work out any inputs from that. Try listing them." : nil
                    }
                }
            }
        } else {
            plan = SceneBuilder.plan(from: description)
            if plan == nil { message = "Couldn't work out any inputs from that. Try listing them, like \"2 vox, acoustic, bass, drums\"." }
        }
    }
}

/// The plan as an editable list: rename, change the source, reorder or remove channels, and
/// edit the monitor mixes.
private struct PlanEditor: View {
    @Binding var plan: ScenePlan

    var body: some View {
        Section {
            TextField("Scene title", text: $plan.title)
                .font(.system(size: 17, weight: .semibold))
        }
        Section {
            ForEach($plan.inputs) { $input in
                HStack(spacing: 10) {
                    Text("\((plan.inputs.firstIndex { $0.id == input.id } ?? 0) + 1)")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 24, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.scribble(input.group.color))
                        .frame(width: 6, height: 28)
                    TextField("Name", text: Binding(get: { input.name }, set: { input.name = SceneBuilder.deskName($0) }))
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: 160, alignment: .leading)
                    Spacer()
                    Menu {
                        ForEach(StarterPresets.Category.allCases) { category in
                            Section(category.rawValue) {
                                ForEach(StarterPresets.all.filter { $0.category == category }) { s in
                                    Button {
                                        input.starter = s.name
                                        input.group = ScenePlan.Group.of(starter: s.name)
                                    } label: { Label(s.name, systemImage: s.symbol) }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: StarterPresets.named(input.starter)?.symbol ?? "questionmark")
                            Text(input.starter)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.raised2))
                    }
                    Text(input.group.dcaName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 60, alignment: .leading)
                }
            }
            .onDelete { plan.inputs.remove(atOffsets: $0) }
            .onMove { plan.inputs.move(fromOffsets: $0, toOffset: $1) }
            if plan.inputs.count < 32 {
                Button {
                    plan.inputs.append(ScenePlan.Input("Ch \(plan.inputs.count + 1)", "Speech", .speech))
                } label: { Label("Add a channel", systemImage: "plus") }
            }
        } header: {
            HStack {
                Text("\(plan.inputs.count) channels")
                Spacer()
                EditButton().font(.system(size: 13))
            }
        }
        Section {
            ForEach(plan.mixes.indices, id: \.self) { i in
                HStack {
                    Text("Bus \(i + 1)")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 50, alignment: .leading)
                    TextField("Mix name", text: Binding(get: { plan.mixes.indices.contains(i) ? plan.mixes[i] : "" },
                                                        set: { if plan.mixes.indices.contains(i) { plan.mixes[i] = SceneBuilder.deskName($0) } }))
                }
            }
            .onDelete { plan.mixes.remove(atOffsets: $0) }
            if plan.mixes.count < 12 {
                Button {
                    plan.mixes.append("Mix \(plan.mixes.count + 1)")
                } label: { Label("Add a monitor mix", systemImage: "plus") }
            }
        } header: {
            Text(plan.mixes.isEmpty ? "No monitor mixes" : "Monitor mixes")
        } footer: {
            if !plan.dcas.isEmpty {
                Text("DCAs: " + plan.dcas.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " · "))
            }
        }
    }
}
