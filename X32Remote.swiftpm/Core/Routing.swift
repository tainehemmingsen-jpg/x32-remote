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

    static func offered(_ block: Block) -> Int {
        block.options.count == auxCodes.count ? offeredAuxOptions : offeredChannelOptions
    }

    /// "AN9-16" -> "Local 9–16", "A1-8" -> "AES50-A 1–8", "CARD1-8" -> "Card 1–8".
    static func label(_ code: String) -> String {
        let prefixes = [("CARD", "Card "), ("AUX", "Local aux "), ("UIN", "UIN "), ("AN", "Local "), ("A", "AES50-A "), ("B", "AES50-B ")]
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
