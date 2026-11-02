import Foundation

/// The desk routing that puts the solo bus on two USB channels.
enum ListenRouting {
    /// A pair of local outputs carrying Monitor L/R, and the block of eight USB channels they reach.
    struct Plan: Equatable {
        /// Local output for the left side (1-15, odd); the right is the next one.
        var output: Int

        /// The card block of eight that carries these outputs ("Out 9-16" for 15/16).
        var cardBlockPath: String {
            output <= 8 ? "/config/routing/CARD/17-24" : "/config/routing/CARD/25-32"
        }
        /// The value for that block: Out 1-8 or Out 9-16.
        var cardBlockValue: Int {
            output <= 8 ? OutputRouting.digitalCodes.firstIndex(of: "OUT1-8")! : OutputRouting.digitalCodes.firstIndex(of: "OUT9-16")!
        }
        /// USB channels the solo bus arrives on (1-based).
        // Card 17-24 carries outs 1-8 and card 25-32 carries outs 9-16: either way, out N is USB 16+N.
        var usbLeft: Int { 16 + output }
        var usbRight: Int { usbLeft + 1 }

        /// Monitor L and Monitor R as /outputs/main/N/src values.
        static let monitorL = Outputs.sourceNames.firstIndex(of: "Monitor L")!
        static let monitorR = Outputs.sourceNames.firstIndex(of: "Monitor R")!

        var changes: [(String, OSCArg)] {
            [
                (Outputs.path(.main, output, "src"), .int(Int32(Plan.monitorL))),
                (Outputs.path(.main, output + 1, "src"), .int(Int32(Plan.monitorR))),
                (cardBlockPath, .int(Int32(cardBlockValue))),
            ]
        }

        /// True when the desk already sends solo to these USB channels.
        func isSet(_ value: (String) -> OSCArg?) -> Bool {
            changes.allSatisfy { value($0.0) == $0.1 }
        }

        /// The addresses to read before showing or changing anything.
        var addresses: [String] { changes.map(\.0) }

        /// The choices offered: 15/16 (default, USB 31/32) and 7/8 (USB 23/24).
        static let choices = [Plan(output: 15), Plan(output: 7)]
    }
}
