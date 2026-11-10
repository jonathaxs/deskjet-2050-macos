import Foundation
import LEDM

/// One ink cartridge as the printer reports it.
struct Cartridge: Identifiable, Sendable {
    let label: String   // "K", "CMY"
    let name: String    // "Black", "Tri-color"
    let state: String   // "newGenuineHP", "genuineHP", "nonHP", "missing" ...
    let level: Int?     // percent, nil when the printer does not know

    var id: String { label }

    /// Whether the printer says this is an HP cartridge, a refilled one, another brand, or none.
    enum Origin { case genuine, refilled, notHP, missing, unknown }

    var origin: Origin {
        let s = state.lowercased()
        if s == "missing" { return .missing }
        if s.contains("refilled") { return .refilled }
        if s.hasPrefix("non") || s.contains("counterfeit") { return .notHP }
        if s.contains("genuinehp") { return .genuine }
        return .unknown
    }
}

/// What came back from the printer.
enum InkReading: Sendable {
    case levels([Cartridge], lowThreshold: Int)
    case notFound   // off or unplugged
    case busy       // another program is using the printer (a print job, for example)
    case noReply
}

enum Printer {
    /// Reads the ink levels over USB. Blocks for up to a few seconds, so call it off the main thread.
    static func readInk() -> InkReading {
        var levels = ledm_levels()
        let result = ledm_read(&levels, nil, 0)
        switch result {
        case LEDM_NOT_FOUND: return .notFound
        case LEDM_BUSY: return .busy
        case ..<0: return .noReply
        default: break
        }
        let supplies = withUnsafeBytes(of: &levels.supplies) { raw in
            Array(raw.bindMemory(to: ledm_supply.self).prefix(Int(levels.count)))
        }
        let cartridges = supplies.map { supply in
            var supply = supply
            return Cartridge(
                label: text(&supply.label),
                name: String(cString: ledm_supply_name(&supply)),
                state: text(&supply.state),
                level: supply.level >= 0 ? Int(supply.level) : nil
            )
        }
        return .levels(cartridges, lowThreshold: Int(levels.low_threshold))
    }

    /// Turns a fixed C char array into a String.
    private static func text<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
