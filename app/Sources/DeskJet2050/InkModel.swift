import Foundation
import Observation

/// Keeps the last ink reading and refreshes it.
@MainActor
@Observable
final class InkModel {
    enum Status {
        case loading
        case levels([Cartridge], lowThreshold: Int)
        case notFound
        case busy
        case noReply
    }

    private(set) var status: Status = .loading
    private(set) var lastUpdate: Date?
    private(set) var isReading = false

    /// Last levels read, kept on screen while a new reading runs or when the printer is busy.
    private(set) var lastLevels: (cartridges: [Cartridge], lowThreshold: Int)?

    init() {}

    /// For previews and screenshots: a model that already has a reading.
    init(sample status: Status, updated: Date = .now) {
        self.status = status
        self.lastUpdate = updated
        if case .levels(let c, let low) = status {
            lastLevels = (c, low)
        }
    }

    /// Reads the printer. When it is busy (usually printing), tries again a few times.
    func refresh() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        if lastLevels == nil {
            status = .loading
        }
        var reading = InkReading.noReply
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1.5))
            }
            reading = await Task.detached { Printer.readInk() }.value
            if case .busy = reading { continue }
            break
        }
        switch reading {
        case .levels(let cartridges, let low):
            status = .levels(cartridges, lowThreshold: low)
            lastLevels = (cartridges, low)
            lastUpdate = .now
        case .notFound:
            status = .notFound
        case .busy:
            status = .busy
        case .noReply:
            status = .noReply
        }
    }

    /// Refreshes only when the last reading is older than the given time (when the window comes back).
    func refreshIfOld(_ seconds: TimeInterval = 30) async {
        if let lastUpdate, Date.now.timeIntervalSince(lastUpdate) < seconds { return }
        await refresh()
    }
}
