import SwiftUI

/// Scenes, in one place:
/// - Snapshots: this app's own, like a DiGiCo: store the desk, choose what each one recalls,
///   protect channels with recall safes, fade faders, step through with GO.
/// - Desk scenes: the X32's own scene list (and cues and snippets), recalled and saved on the desk.
/// - Scene files: X32-Edit .scn files kept on this iPad, sent to the desk when you want them.
struct ScenesSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "scenes.tab") ?? "") ?? .snapshots

    enum Tab: String, CaseIterable, Identifiable {
        case snapshots, desk, files
        var id: String { rawValue }
        var title: String {
            switch self {
            case .snapshots: return "Snapshots"
            case .desk: return "Desk scenes"
            case .files: return "Scene files"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .snapshots: SnapshotsView(app: app)
                case .desk: ShowSheet(app: app, embedded: true)
                case .files: SceneLibrarySheet(app: app, embedded: true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Scenes", selection: $tab) {
                        ForEach(Tab.allCases) { t in Text(t.title).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: tab) { _, t in UserDefaults.standard.set(t.rawValue, forKey: "scenes.tab") }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Snapshots

struct SnapshotsView: View {
    let app: AppModel
    @State private var selected: Int?
    @State private var editing: Int?
    @State private var showingSafes = false
    @State private var confirmDelete: Int?

    var body: some View {
        let show = app.snapshots
        List {
            Section {
                GoPanel(app: app)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                if show.count == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No snapshots yet")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Set the desk up for the first part of the show and tap Store. Each snapshot remembers the desk; choose what it recalls with Scope, and protect channels with Recall safes.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(0..<show.count, id: \.self) { i in
                    SnapshotRow(app: app, index: i, selected: selected == i) {
                        selected = i
                    } recall: {
                        app.recallSnapshot(at: i)
                        selected = i
                    } edit: {
                        editing = i
                    }
                    .contextMenu {
                        Button { app.recallSnapshot(at: i) } label: { Label("Recall", systemImage: "play.fill") }
                        Button { app.updateSnapshot(at: i) } label: { Label("Update from the desk", systemImage: "arrow.triangle.2.circlepath") }
                        Button { editing = i } label: { Label("Name, scope and fade…", systemImage: "slider.horizontal.3") }
                        Button { app.editSnapshots { _ = $0.duplicate(at: i) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { confirmDelete = i } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions {
                        Button(role: .destructive) { confirmDelete = i } label: { Label("Delete", systemImage: "trash") }
                        Button { app.updateSnapshot(at: i) } label: { Label("Update", systemImage: "arrow.triangle.2.circlepath") }
                            .tint(Theme.accent)
                    }
                }
                .onMove { from, to in app.editSnapshots { $0.move(fromOffsets: from, toOffset: to) } }
            } header: {
                HStack {
                    Text(show.count == 0 ? "" : "\(show.count) snapshots")
                    Spacer()
                    Button {
                        showingSafes = true
                    } label: {
                        Label(show.safes.isEmpty ? "Recall safes" : "Recall safes (on)", systemImage: "lock.shield")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(show.safes.isEmpty ? Theme.secondary : Theme.solo)
                }
            } footer: {
                if show.count > 0 {
                    Text("Tap a snapshot's play button to recall it, or GO for the next one. Touch and hold for update, scope and fade. Each recall is one Undo step.")
                }
            }
        }
        .onAppear { app.loadSnapshotValues() }
        .sheet(item: Binding(get: { editing.map(EditIndex.init) }, set: { editing = $0?.index })) { e in
            SnapshotEditor(app: app, index: e.index)
        }
        .sheet(isPresented: $showingSafes) {
            RecallSafesEditor(app: app)
        }
        .confirmationDialog("Delete “\(confirmDelete.map { app.snapshots[$0].name } ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete snapshot", role: .destructive) {
                if let i = confirmDelete { app.editSnapshots { $0.delete(at: i) } }
                confirmDelete = nil
            }
        }
    }

    private struct EditIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

/// Current and next, with Previous, GO and Store, like the snapshot keys on a DiGiCo.
private struct GoPanel: View {
    let app: AppModel

    var body: some View {
        let show = app.snapshots
        let current = show.current
        let next = show.nextIndex.map { show[$0] }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.map { "\($0.number). \($0.name)" } ?? "Nothing recalled yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(current == nil ? Theme.secondary : Theme.text)
                    .lineLimit(1)
                Text(next.map { "Next: \($0.number). \($0.name)" } ?? (show.count == 0 ? "Store the desk to make the first one" : "End of the list"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                if app.snapshotFading {
                    Label("Fading…", systemImage: "slowmo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 8)
            PanelKey(title: "Previous", symbol: "backward.end.fill", enabled: show.previousIndex != nil) {
                app.goPreviousSnapshot()
            }
            PanelKey(title: "Store", symbol: "plus", enabled: true) {
                app.storeSnapshot()
            }
            Button {
                app.goNextSnapshot()
            } label: {
                Text("GO")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 110, height: 72)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(show.nextIndex == nil ? Theme.raised2 : Theme.on))
            }
            .buttonStyle(ConsoleKeyStyle())
            .disabled(show.nextIndex == nil)
            .accessibilityLabel(next.map { "Go to \($0.name)" } ?? "Go")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
    }
}

private struct PanelKey: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .frame(width: 80, height: 72)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised2))
        }
        .buttonStyle(ConsoleKeyStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct SnapshotRow: View {
    let app: AppModel
    let index: Int
    let selected: Bool
    let select: () -> Void
    let recall: () -> Void
    let edit: () -> Void

    var body: some View {
        let snap = app.snapshots[index]
        let isCurrent = app.snapshots.currentIndex == index
        HStack(spacing: 12) {
            Text("\(snap.number)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.black : Theme.secondary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isCurrent ? Theme.accent : Theme.raised2))
            VStack(alignment: .leading, spacing: 3) {
                Text(snap.name)
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                Text(snap.summary + (snap.isSnap ? "" : String(format: " · %.1f s fade", snap.fadeTime)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                if !snap.notes.isEmpty {
                    Text(snap.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: edit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(ConsoleKeyStyle())
            .accessibilityLabel("Scope and fade for \(snap.name)")
            Button(action: recall) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
                    .frame(width: 52, height: 40)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.on))
            }
            .buttonStyle(ConsoleKeyStyle())
            .accessibilityLabel("Recall \(snap.name)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .listRowBackground(selected ? Theme.raised : Color.clear)
    }
}

// MARK: - Editing a snapshot

/// Name, notes, fade time and scope (which strips and which kinds of setting it recalls).
private struct SnapshotEditor: View {
    let app: AppModel
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var snap: Snapshot

    init(app: AppModel, index: Int) {
        self.app = app
        self.index = index
        _snap = State(initialValue: app.snapshots[index])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $snap.name)
                    TextField("Notes", text: $snap.notes, axis: .vertical)
                }
                Section {
                    Stepper(value: $snap.fadeTime, in: 0...30, step: 0.5) {
                        HStack {
                            Text("Fade time")
                            Spacer()
                            Text(snap.fadeTime == 0 ? "Snap" : String(format: "%.1f s", snap.fadeTime))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                } footer: {
                    Text("Faders and send levels glide to the snapshot over this time; everything else changes at once.")
                }
                Section {
                    TypeGrid(types: $snap.scope.types)
                } header: {
                    Text("Recalls")
                } footer: {
                    Text("Preamps and names are off for new snapshots, so a recall doesn't change gain, 48V or labels unless you want it to.")
                }
                Section {
                    StripGrid(selection: $snap.scope.strips)
                } header: {
                    Text("On these strips")
                }
            }
            .navigationTitle("Snapshot \(snap.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let edited = snap
                        app.editSnapshot(at: index) { s in
                            s.name = edited.name.isEmpty ? s.name : edited.name
                            s.notes = edited.notes
                            s.fadeTime = edited.fadeTime
                            s.scope = edited.scope
                        }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Recall safes for the whole show: strips and kinds of setting no snapshot will touch.
private struct RecallSafesEditor: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var safes: RecallSafes

    init(app: AppModel) {
        self.app = app
        _safes = State(initialValue: app.snapshots.safes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TypeGrid(types: $safes.types)
                } header: {
                    Text("Never recall")
                } footer: {
                    Text("These kinds of setting stay as they are on every strip, whatever a snapshot says.")
                }
                Section {
                    StripGrid(selection: $safes.strips)
                } header: {
                    Text("Safe strips")
                } footer: {
                    Text("Snapshots never change these strips at all: the MC's mic, a playback channel the venue controls.")
                }
            }
            .navigationTitle("Recall safes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = safes
                        app.editSnapshots { $0.safes = s }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The kinds of setting, as toggle keys.
private struct TypeGrid: View {
    @Binding var types: Set<Snapshot.ParamType>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Snapshot.ParamType.allCases, id: \.self) { t in
                let on = types.contains(t)
                LitButton(title: t.title, isOn: on, color: Theme.on, height: 40, fontSize: 13, style: .outline) {
                    if on { types.remove(t) } else { types.insert(t) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Every strip as a key, grouped like the desk's layers, with all/none per group.
private struct StripGrid: View {
    @Binding var selection: Set<StripID>

    private var groups: [(String, [StripID])] {
        [
            ("Channels", StripID.all(.channel)),
            ("Aux in", StripID.all(.auxIn)),
            ("FX returns", StripID.all(.fxReturn)),
            ("Mix buses", StripID.all(.bus)),
            ("Matrices", StripID.all(.matrix)),
            ("Main", [StripID.mainLR, StripID.monoC]),
            ("DCAs", StripID.all(.dca)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.0) { title, strips in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("All") { selection.formUnion(strips) }
                            .font(.system(size: 13))
                        Button("None") { selection.subtract(strips) }
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(strips) { s in
                            let on = selection.contains(s)
                            LitButton(title: s.footLabel, isOn: on, color: Theme.accent, height: 34, fontSize: 12) {
                                if on { selection.remove(s) } else { selection.insert(s) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
