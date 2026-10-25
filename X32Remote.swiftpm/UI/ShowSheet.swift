import SwiftUI

/// The desk's show: a cue list with GO, scenes (with save), and snippets. Every recall asks first,
/// because it changes the desk straight away.
struct ShowSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Show.Control
    @State private var pending: Recall?
    @State private var confirming = false

    struct Recall: Identifiable {
        let control: Show.Control
        let number: Int
        var id: String { "\(control.rawValue)-\(number)" }
    }

    init(app: AppModel) {
        self.app = app
        // Open on whatever the desk's own GO button works with.
        let deskTab = Show.Control(rawValue: app.param(Show.controlPath).int(or: 1)) ?? .scenes
        _tab = State(initialValue: app.autoShowTab ?? deskTab)
    }

    var body: some View {
        let deskControl = Show.Control(rawValue: app.param(Show.controlPath).int(or: -1))
        let current = app.param(Show.currentPath).int(or: -1)
        let showName = app.param(Show.namePath).string
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $tab) {
                        ForEach(Show.Control.allCases) { c in
                            Text(c.title).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    if !showName.isEmpty {
                        Text("Show: \(showName)")
                    }
                }
                switch tab {
                case .cues:
                    CueList(app: app, current: deskControl == .cues ? current : -1) { pending = $0; confirming = true }
                case .scenes:
                    SceneList(app: app, current: deskControl == .scenes ? current : -1) { pending = $0; confirming = true }
                case .snippets:
                    SnippetList(app: app, current: deskControl == .snippets ? current : -1) { pending = $0; confirming = true }
                }
            }
            .overlay(alignment: .bottom) {
                ToastView(app: app)
            }
            .navigationTitle("Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: tab, initial: true) { _, newTab in
                app.loadShow(newTab)
            }
            .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible, presenting: pending) { r in
                Button("Recall \(r.control.singular)", role: .destructive) {
                    app.recall(r.control, r.number)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { r in
                Text(r.control == .snippets
                     ? "This changes the parts of the desk the snippet covers, straight away."
                     : "This changes the desk straight away: faders, mutes, EQ and routing.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var confirmTitle: String {
        guard let r = pending else { return "" }
        let name = app.param(r.control.path(r.number, "name")).string
        switch r.control {
        case .cues:
            let numb = app.param(r.control.path(r.number, "numb")).int(or: -1)
            return "Go to cue \(Show.cueNumber(numb))" + (name.isEmpty ? "?" : " “\(name)”?")
        case .scenes:
            return String(format: "Recall scene %02d", r.number) + (name.isEmpty ? "?" : " “\(name)”?")
        case .snippets:
            return String(format: "Recall snippet %02d", r.number) + (name.isEmpty ? "?" : " “\(name)”?")
        }
    }
}

// MARK: - Cues

private struct CueList: View {
    let app: AppModel
    /// The desk's current cue, or -1 when the desk isn't in cue mode.
    let current: Int
    let ask: (ShowSheet.Recall) -> Void

    private func exists(_ n: Int) -> Bool? {
        let name = app.param(Show.cuePath(n, "name"))
        let numb = app.param(Show.cuePath(n, "numb"))
        guard name.isKnown && numb.isKnown else { return nil }
        return !name.string.isEmpty || numb.int > 0
    }

    var body: some View {
        let cues = (0..<Show.Control.cues.count).filter { exists($0) == true }
        let allRead = (0..<Show.Control.cues.count).allSatisfy { exists($0) != nil }
        let next = Show.nextCue(after: current, exists: exists) { app.param(Show.cuePath($0, "skip")).bool }
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(current >= 0 ? "Current: " + cueTitle(current) : "No current cue")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                    Text(next.map { "Next: " + cueTitle($0) } ?? (allRead ? "End of the cue list" : "Reading cues…"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    if let n = next { ask(ShowSheet.Recall(control: .cues, number: n)) }
                } label: {
                    Text("GO")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: 92, height: 54)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.on))
                }
                .buttonStyle(.plain)
                .disabled(next == nil)
                .opacity(next == nil ? 0.4 : 1)
                .accessibilityLabel("Go to the next cue")
            }
        }
        Section {
            if cues.isEmpty {
                Text(allRead ? "No cues in this show." : "Reading cues from the desk…")
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(cues, id: \.self) { n in
                CueRow(app: app, number: n, isCurrent: n == current) {
                    ask(ShowSheet.Recall(control: .cues, number: n))
                }
            }
        }
    }

    private func cueTitle(_ n: Int) -> String {
        let numb = app.param(Show.cuePath(n, "numb")).int(or: -1)
        let name = app.param(Show.cuePath(n, "name")).string
        return Show.cueNumber(numb) + (name.isEmpty ? "" : " \(name)")
    }
}

private struct CueRow: View {
    let app: AppModel
    let number: Int
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        let numb = app.param(Show.cuePath(number, "numb")).int(or: -1)
        let name = app.param(Show.cuePath(number, "name")).string
        let skip = app.param(Show.cuePath(number, "skip")).bool
        let scene = Show.cueScene(scene: app.param(Show.cuePath(number, "scene")).int(or: -1))
        let snippet = Show.cueSnippet(bit: app.param(Show.cuePath(number, "bit")).int(or: -1))
        let detail: String = {
            var parts: [String] = []
            if let s = scene {
                let sceneName = app.param(Show.scenePath(s, "name")).string
                parts.append(String(format: "Scene %02d", s) + (sceneName.isEmpty ? "" : " \(sceneName)"))
            }
            if let s = snippet {
                let snippetName = app.param(Show.snippetPath(s, "name")).string
                parts.append(String(format: "Snippet %02d", s) + (snippetName.isEmpty ? "" : " \(snippetName)"))
            }
            if skip { parts.append("Skipped") }
            return parts.joined(separator: " · ")
        }()
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(Show.cueNumber(numb))
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.secondary)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Untitled" : name)
                        .font(.system(size: 17, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(Theme.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isCurrent {
                    CurrentBadge()
                }
            }
            .contentShape(Rectangle())
            .opacity(skip ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cue \(Show.cueNumber(numb)) \(name)" + (skip ? ", skipped" : "") + (isCurrent ? ", current" : ""))
    }
}

// MARK: - Scenes

private struct SceneList: View {
    let app: AppModel
    let current: Int
    let ask: (ShowSheet.Recall) -> Void

    var body: some View {
        let scenes = (0..<100).filter { app.param(Show.scenePath($0, "hasdata")).bool }
        Section {
            SaveSceneRow(app: app, current: current, usedScenes: Set(scenes))
        } header: {
            Text("Save the desk as a scene")
        }
        Section {
            if scenes.isEmpty {
                if app.pendingRequests > 0 {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading scenes from the desk…")
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    Text("No scenes saved on this desk yet.")
                        .foregroundStyle(Theme.secondary)
                }
            }
            ForEach(scenes, id: \.self) { n in
                NumberedRow(app: app, control: .scenes, number: n, isCurrent: n == current) {
                    ask(ShowSheet.Recall(control: .scenes, number: n))
                }
            }
        }
    }
}

// MARK: - Snippets

private struct SnippetList: View {
    let app: AppModel
    let current: Int
    let ask: (ShowSheet.Recall) -> Void

    var body: some View {
        let snippets = (0..<100).filter { app.param(Show.snippetPath($0, "hasdata")).bool }
        Section {
            if snippets.isEmpty {
                Text(app.pendingRequests > 0 ? "Reading snippets from the desk…" : "No snippets saved on this desk yet.")
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(snippets, id: \.self) { n in
                NumberedRow(app: app, control: .snippets, number: n, isCurrent: n == current) {
                    ask(ShowSheet.Recall(control: .snippets, number: n))
                }
            }
        } footer: {
            Text("A snippet changes only the channels and settings it was saved with.")
        }
    }
}

/// A scene or snippet row: number, name, current marker.
private struct NumberedRow: View {
    let app: AppModel
    let control: Show.Control
    let number: Int
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        let name = app.param(control.path(number, "name")).string
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.secondary)
                    .frame(width: 34, alignment: .leading)
                Text(name.isEmpty ? "Untitled" : name)
                    .font(.system(size: 17, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(Theme.text)
                Spacer()
                if isCurrent {
                    CurrentBadge()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(control.singular.capitalized) \(number) \(name)" + (isCurrent ? ", current" : ""))
    }
}

private struct CurrentBadge: View {
    var body: some View {
        Text("CURRENT")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent))
    }
}

/// Save the desk's state as a scene.
struct SaveSceneRow: View {
    let app: AppModel
    let current: Int
    let usedScenes: Set<Int>
    @State private var name = ""
    @State private var number = -1
    @State private var confirmOverwrite = false

    var body: some View {
        let target = number >= 0 ? number : defaultNumber
        // Until the desk has said whether a slot is empty, assume it isn't (never overwrite blindly).
        let targetKnown = app.param(Show.scenePath(target, "hasdata")).isKnown
        let targetUsed = usedScenes.contains(target) || !targetKnown
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Scene name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Number", selection: Binding(get: { target }, set: { number = $0 })) {
                    ForEach(0..<100, id: \.self) { n in
                        Text(String(format: "%02d", n) + (usedScenes.contains(n) ? " (used)" : "")).tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                Button("Save") {
                    if targetUsed {
                        confirmOverwrite = true
                    } else {
                        app.saveScene(target, name: name)
                        name = ""
                        number = -1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Text(!targetKnown
                 ? "Still reading the scene list from the desk…"
                 : usedScenes.contains(target)
                 ? String(format: "Scene %02d already has a scene in it; saving replaces it.", target)
                 : "Saves faders, mutes, EQ, dynamics and routing as they are now.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .confirmationDialog(String(format: "Replace scene %02d?", target), isPresented: $confirmOverwrite, titleVisibility: .visible) {
            Button("Replace", role: .destructive) {
                app.saveScene(target, name: name)
                name = ""
                number = -1
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The scene that's there now will be lost.")
        }
    }

    /// The first empty slot after the current scene (or the first empty one).
    private var defaultNumber: Int {
        let start = max(current, -1) + 1
        for n in start..<100 where !usedScenes.contains(n) { return n }
        for n in 0..<100 where !usedScenes.contains(n) { return n }
        return max(current, 0)
    }
}
