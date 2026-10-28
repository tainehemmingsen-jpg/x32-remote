import Foundation

/// An X32 scene file (.scn): the text format the desk and X32-Edit save scenes in. A header
/// line, then one "node" line per block of settings, e.g. `/ch/01/config "Kick" 1 RD 1`.
/// The desk takes those lines back as they are (sent to "/" as a string).
struct SceneFile: Codable, Identifiable, Equatable {
    enum Origin: String, Codable {
        case imported, desk, builder, demo

        var title: String {
            switch self {
            case .imported: return "Imported"
            case .desk: return "Saved from the desk"
            case .builder: return "Built in the app"
            case .demo: return "Demo desk"
            }
        }
    }

    var id = UUID()
    var name: String
    var note: String
    var created = Date()
    var origin: Origin
    /// The node lines, without the header.
    var lines: [String]

    /// Parts of a scene that can be left out when sending it to the desk.
    enum Part: String, CaseIterable, Identifiable {
        case channels, buses, effects, routing, preamps
        var id: String { rawValue }

        var title: String {
            switch self {
            case .channels: return "Channels, aux ins and FX returns"
            case .buses: return "Mix buses, matrices, main and DCAs"
            case .effects: return "Effects"
            case .routing: return "Routing and outputs"
            case .preamps: return "Preamp gain and 48V"
            }
        }

        /// Off by default: preamps set wrongly can be loud, and 48V can harm some gear.
        var onByDefault: Bool { self != .preamps }

        func contains(_ path: String) -> Bool {
            switch self {
            case .channels: return path.hasPrefix("/ch/") || path.hasPrefix("/auxin/") || path.hasPrefix("/fxrtn/")
            case .buses:
                return path.hasPrefix("/bus/") || path.hasPrefix("/mtx/") || path.hasPrefix("/main/") || path.hasPrefix("/dca/")
                    || (path.hasPrefix("/config/") && !path.hasPrefix("/config/routing"))
            case .effects: return path.hasPrefix("/fx/")
            case .routing: return path.hasPrefix("/config/routing") || path.hasPrefix("/outputs/")
            case .preamps: return path.hasPrefix("/headamp/")
            }
        }

        static func of(_ path: String) -> Part? {
            allCases.first { $0.contains(path) }
        }
    }

    /// The node path a line sets ("/ch/01/config").
    static func path(of line: String) -> String {
        String(line.split(separator: " ", maxSplits: 1).first ?? "")
    }

    /// The lines to send, leaving out the parts not wanted.
    func lines(including parts: Set<Part>) -> [String] {
        lines.filter { line in
            guard let part = Part.of(SceneFile.path(of: line)) else { return false }
            return parts.contains(part)
        }
    }

    // MARK: Reading and writing

    /// Reads a .scn file. Returns nil if it has no node lines at all.
    static func parse(_ text: String, fallbackName: String, origin: Origin = .imported) -> SceneFile? {
        var name = fallbackName
        var note = ""
        var lines: [String] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                // Header: #2.7# "name" "note" %000000000 1 ...
                let quoted = SceneFile.quotedStrings(in: line)
                if let n = quoted.first, !n.isEmpty { name = n }
                if quoted.count > 1 { note = quoted[1] }
                continue
            }
            guard line.hasPrefix("/"), line.count > 1 else { continue }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return SceneFile(name: name, note: note, origin: origin, lines: lines)
    }

    /// The file as X32-Edit and the desk expect it.
    func text(firmware: String = "4.0") -> String {
        let version = firmware.hasPrefix("2") || firmware.hasPrefix("3") ? "2.7" : "4.0"
        var out = "#\(version)# \"\(SceneFile.escape(name))\" \"\(SceneFile.escape(note))\" %000000000 1 X32Remote\n"
        for line in lines { out += line + "\n" }
        return out
    }

    /// A safe file name for exporting.
    var fileName: String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }
        let base = String(cleaned).trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Scene" : base) + ".scn"
    }

    // MARK: What's in it

    /// Channel names from the scene's /ch/NN/config lines, for a quick look at what it is.
    var channelNames: [String] {
        lines.compactMap { line -> String? in
            guard line.hasPrefix("/ch/"), SceneFile.path(of: line).hasSuffix("/config") else { return nil }
            let name = SceneFile.quotedStrings(in: line).first ?? ""
            return name.isEmpty ? nil : name
        }
    }

    var summary: String {
        let names = channelNames
        if names.isEmpty { return "\(lines.count) settings" }
        let shown = names.prefix(8).joined(separator: ", ")
        return names.count > 8 ? shown + " +\(names.count - 8) more" : shown
    }

    static func quotedStrings(in line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inside = false
        var escaped = false
        for ch in line {
            if inside {
                if escaped { current.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { result.append(current); current = ""; inside = false; continue }
                current.append(ch)
            } else if ch == "\"" {
                inside = true
            }
        }
        return result
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
    }

    /// The node path (without its leading slash) to ask the desk for with /node.
    static func nodeRequest(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}

// MARK: - Understanding a few node lines

extension SceneFile {
    /// Scribble-strip colours as scene files write them (0-15).
    static let colorCodes = ["OFF", "RD", "GN", "YE", "BL", "MG", "CY", "WH", "OFFi", "RDi", "GNi", "YEi", "BLi", "MGi", "CYi", "WHi"]

    /// Splits a node line into its path and values (quoted strings kept whole, quotes removed).
    static func tokens(_ line: String) -> (path: String, values: [String]) {
        var out: [String] = []
        var current = ""
        var inQuote = false
        var wasQuoted = false
        for ch in line {
            if ch == "\"" { inQuote.toggle(); wasQuoted = true; continue }
            if ch == " " && !inQuote {
                if !current.isEmpty || wasQuoted { out.append(current) }
                current = ""
                wasQuoted = false
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty || wasQuoted { out.append(current) }
        guard let first = out.first else { return ("", []) }
        return (first, Array(out.dropFirst()))
    }

    /// The parameter changes in a config or mix line (name, colour, on, fader). Other lines give
    /// nothing; the desk itself understands every line, this is only for the demo desk.
    static func basicChanges(_ line: String) -> [(String, OSCArg)] {
        let (path, v) = tokens(line)
        guard !v.isEmpty else { return [] }
        if path.hasSuffix("/config") {
            let base = String(path.dropLast("/config".count))
            var out: [(String, OSCArg)] = [(base + "/config/name", .string(v[0]))]
            if v.count >= 3, let c = colorCodes.firstIndex(of: v[2]) {
                out.append((base + "/config/color", .int(Int32(c))))
            }
            return out
        }
        if path.hasSuffix("/mix") || (path.hasPrefix("/dca/") && path.split(separator: "/").count == 2) {
            let base = path
            var out: [(String, OSCArg)] = [(base + "/on", .int(v[0] == "ON" ? 1 : 0))]
            if v.count >= 2 {
                let db: Float = v[1].hasPrefix("-oo") ? -.infinity : (Float(v[1]) ?? 0)
                out.append((base + "/fader", .float(X32Math.quantize(X32Math.dbToFader(db), steps: 1023))))
            }
            return out
        }
        return []
    }

    /// A config line as the desk writes it, from what the app knows (for the demo desk).
    static func configLine(_ path: String, name: String, color: Int, source: Int) -> String {
        let code = colorCodes.indices.contains(color) ? colorCodes[color] : "OFF"
        return "\(path) \"\(escape(name))\" 1 \(code) \(source)"
    }
}

/// Scenes kept on this iPad, in the app's own files.
enum SceneLibrary {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SceneLibrary.json")
    }

    static func load(from url: URL = SceneLibrary.url) -> [SceneFile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SceneFile].self, from: data)) ?? []
    }

    static func save(_ scenes: [SceneFile], to url: URL = SceneLibrary.url) {
        if let data = try? JSONEncoder().encode(scenes) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
