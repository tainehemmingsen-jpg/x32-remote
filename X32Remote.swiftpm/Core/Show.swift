import Foundation

/// The desk's show: cues (which recall a scene and/or a snippet), scenes and snippets.
enum Show {
    /// What the desk's own GO button and "current position" refer to: 0 cues, 1 scenes, 2 snippets.
    static let controlPath = "/-prefs/show_control"
    static let currentPath = "/-show/prepos/current"
    static let namePath = "/-show/showfile/show/name"

    enum Control: Int, CaseIterable, Identifiable {
        case cues = 0, scenes, snippets

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .cues: return "Cues"
            case .scenes: return "Scenes"
            case .snippets: return "Snippets"
            }
        }

        var singular: String {
            switch self {
            case .cues: return "cue"
            case .scenes: return "scene"
            case .snippets: return "snippet"
            }
        }

        var count: Int {
            switch self {
            case .cues: return 500
            case .scenes, .snippets: return 100
            }
        }

        var goAction: String {
            switch self {
            case .cues: return "/-action/gocue"
            case .scenes: return "/-action/goscene"
            case .snippets: return "/-action/gosnippet"
            }
        }

        func path(_ n: Int, _ field: String) -> String {
            String(format: "/-show/showfile/%@/%03d/%@", singular, n, field)
        }
    }

    static func cuePath(_ n: Int, _ field: String) -> String { Control.cues.path(n, field) }
    static func scenePath(_ n: Int, _ field: String) -> String { Control.scenes.path(n, field) }
    static func snippetPath(_ n: Int, _ field: String) -> String { Control.snippets.path(n, field) }

    /// Cue numbers are stored as one int: 1.2.3 is 123, 10.0.0 is 1000.
    static func cueNumber(_ numb: Int) -> String {
        guard numb >= 0 else { return "—" }
        return "\(numb / 100).\(numb / 10 % 10).\(numb % 10)"
    }

    /// Addresses that describe the whole list for a mode (names, plus what tells used from unused).
    static func listAddresses(_ control: Control) -> [String] {
        var a = [currentPath, controlPath]
        for n in 0..<control.count {
            a.append(control.path(n, "name"))
            switch control {
            case .cues: a.append(control.path(n, "numb"))
            case .scenes, .snippets: a.append(control.path(n, "hasdata"))
            }
        }
        return a
    }

    /// The rest of a cue, read once it's known to exist.
    static func cueDetailAddresses(_ n: Int) -> [String] {
        ["skip", "scene", "bit"].map { cuePath(n, $0) }
    }

    /// Which snippet a cue fires (the desk calls the field "bit"), or nil.
    static func cueSnippet(bit: Int) -> Int? { (0..<100).contains(bit) ? bit : nil }
    static func cueScene(scene: Int) -> Int? { (0..<100).contains(scene) ? scene : nil }

    /// The next cue the desk's GO would fire after `current`: the first later cue that exists and
    /// isn't marked skip. `exists` and `skipped` answer for an index; nil from `exists` means not read.
    static func nextCue(after current: Int, exists: (Int) -> Bool?, skipped: (Int) -> Bool) -> Int? {
        var n = max(current, -1) + 1
        while n < Control.cues.count {
            guard let e = exists(n) else { return nil }
            if e && !skipped(n) { return n }
            n += 1
        }
        return nil
    }
}
