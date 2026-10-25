import Foundation

/// Input routing: which physical inputs feed each block of eight channels (and the aux ins).
enum InputRouting {
    struct Block: Identifiable {
        let path: String
        let title: String
        let options: [String]
        var id: String { path }
    }

    /// Desk codes for the channel blocks. The last four (UIN) only exist on newer firmware, so
    /// they're shown when the desk reports them but not offered.
    static let channelCodes = ["AN1-8", "AN9-16", "AN17-24", "AN25-32", "A1-8", "A9-16", "A17-24", "A25-32", "A33-40",
                               "A41-48", "B1-8", "B9-16", "B17-24", "B25-32", "B33-40", "B41-48", "CARD1-8", "CARD9-16",
                               "CARD17-24", "CARD25-32", "UIN1-8", "UIN9-16", "UIN17-24", "UIN25-32"]
    static let auxCodes = ["AUX1-4", "AN1-2", "AN1-4", "AN1-6", "A1-2", "A1-4", "A1-6", "B1-2", "B1-4", "B1-6",
                           "CARD1-2", "CARD1-4", "CARD1-6", "UIN1-2", "UIN1-4", "UIN1-6"]
    static let offeredChannelOptions = 20
    static let offeredAuxOptions = 13

    static let blocks: [Block] = [
        Block(path: "/config/routing/IN/1-8", title: "Ch 1–8", options: channelCodes),
        Block(path: "/config/routing/IN/9-16", title: "Ch 9–16", options: channelCodes),
        Block(path: "/config/routing/IN/17-24", title: "Ch 17–24", options: channelCodes),
        Block(path: "/config/routing/IN/25-32", title: "Ch 25–32", options: channelCodes),
        Block(path: "/config/routing/IN/AUX", title: "Aux in 1–6", options: auxCodes)
    ]

    /// How many of a block's options to offer: the UIN entries at the end of the channel and aux
    /// lists only exist on newer firmware.
    static func offered(_ block: Block) -> Int {
        if block.options == channelCodes { return offeredChannelOptions }
        if block.options == auxCodes { return offeredAuxOptions }
        return block.options.count
    }

    /// "AN9-16" -> "Local in 9–16", "A1-8" -> "AES50-A 1–8", "CARD1-8" -> "Card 1–8", "OUT1-4" -> "Out 1–4".
    static func label(_ code: String) -> String {
        let special = ["AUX/CR": "Aux out / Control room", "AUX/TB": "Aux out / Talkback",
                       "AUX1-6/Mon": "Aux out 1–6 + Monitor", "AuxIN1-6/TB": "Aux in 1–6 + Talkback"]
        if let s = special[code] { return s }
        let prefixes = [("CARD", "Card "), ("AUX", "Local aux in "), ("UIN", "UIN "), ("AN", "Local in "), ("OUT", "Out "),
                        ("P16", "P16 "), ("A", "AES50-A "), ("B", "AES50-B ")]
        for (p, name) in prefixes where code.hasPrefix(p) {
            return name + code.dropFirst(p.count).replacingOccurrences(of: "-", with: "–")
        }
        return code
    }

    static func label(_ block: Block, _ value: Int) -> String {
        block.options.indices.contains(value) ? label(block.options[value]) : "Option \(value)"
    }

    static var addresses: [String] { blocks.map(\.path) }
}

/// Output routing: which signals go to each block of the local XLR outs, the AES50 ports and the
/// expansion card. Plus the record/play switch that chooses between the IN and PLAY input blocks.
enum OutputRouting {
    static let switchPath = "/config/routing/routswitch"
    static let switchNames = ["Record", "Play"]

    /// Signals for local out blocks 1-4 and 9-12 (desk codes).
    static let localCodesA = ["AN1-4", "AN9-12", "AN17-20", "AN25-28", "A1-4", "A9-12", "A17-20", "A25-28", "A33-36",
                              "A41-44", "B1-4", "B9-12", "B17-20", "B25-28", "B33-36", "B41-44", "CARD1-4", "CARD9-12",
                              "CARD17-20", "CARD25-28", "OUT1-4", "OUT9-12", "P161-4", "P169-12", "AUX/CR", "AUX/TB"]
    /// Signals for local out blocks 5-8 and 13-16.
    static let localCodesB = ["AN5-8", "AN13-16", "AN21-24", "AN29-32", "A5-8", "A13-16", "A21-24", "A29-32", "A37-40",
                              "A45-48", "B5-8", "B13-16", "B21-24", "B29-32", "B37-40", "B45-48", "CARD5-8", "CARD13-16",
                              "CARD21-24", "CARD29-32", "OUT5-8", "OUT13-16", "P165-8", "P1613-16", "AUX/CR", "AUX/TB"]
    /// Signals for the AES50 and card blocks of eight.
    static let digitalCodes = ["AN1-8", "AN9-16", "AN17-24", "AN25-32", "A1-8", "A9-16", "A17-24", "A25-32", "A33-40",
                               "A41-48", "B1-8", "B9-16", "B17-24", "B25-32", "B33-40", "B41-48", "CARD1-8", "CARD9-16",
                               "CARD17-24", "CARD25-32", "OUT1-8", "OUT9-16", "P161-8", "P169-16", "AUX1-6/Mon", "AuxIN1-6/TB"]

    static let local: [InputRouting.Block] = [
        InputRouting.Block(path: "/config/routing/OUT/1-4", title: "Out 1–4", options: localCodesA),
        InputRouting.Block(path: "/config/routing/OUT/5-8", title: "Out 5–8", options: localCodesB),
        InputRouting.Block(path: "/config/routing/OUT/9-12", title: "Out 9–12", options: localCodesA),
        InputRouting.Block(path: "/config/routing/OUT/13-16", title: "Out 13–16", options: localCodesB)
    ]
    static let aes50A: [InputRouting.Block] = (0..<6).map {
        InputRouting.Block(path: "/config/routing/AES50A/\($0 * 8 + 1)-\($0 * 8 + 8)", title: "AES50 A \($0 * 8 + 1)–\($0 * 8 + 8)", options: digitalCodes)
    }
    static let aes50B: [InputRouting.Block] = (0..<6).map {
        InputRouting.Block(path: "/config/routing/AES50B/\($0 * 8 + 1)-\($0 * 8 + 8)", title: "AES50 B \($0 * 8 + 1)–\($0 * 8 + 8)", options: digitalCodes)
    }
    static let card: [InputRouting.Block] = (0..<4).map {
        InputRouting.Block(path: "/config/routing/CARD/\($0 * 8 + 1)-\($0 * 8 + 8)", title: "Card \($0 * 8 + 1)–\($0 * 8 + 8)", options: digitalCodes)
    }
    /// The input blocks used while the card plays back (routswitch = Play).
    static let play: [InputRouting.Block] = InputRouting.blocks.map {
        InputRouting.Block(path: $0.path.replacingOccurrences(of: "/IN/", with: "/PLAY/"), title: $0.title, options: $0.options)
    }

    static let sections: [(String, [InputRouting.Block])] = [
        ("Local XLR outs", local), ("AES50 A", aes50A), ("AES50 B", aes50B), ("Card", card)
    ]

    static var addresses: [String] {
        [switchPath] + sections.flatMap { $0.1.map(\.path) } + play.map(\.path)
    }
}
