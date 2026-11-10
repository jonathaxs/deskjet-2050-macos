import SwiftUI

@main
struct DeskJet2050App: App {
    var body: some Scene {
        Window("DeskJet 2050", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

/// First version: proves the app can read the printer. The real screens come next.
struct ContentView: View {
    @State private var reading: InkReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch reading {
            case nil:
                ProgressView("Reading the printer…")
            case .levels(let cartridges, let low)?:
                ForEach(cartridges) { cartridge in
                    Text("\(cartridge.name): \(cartridge.level.map { "\($0)%" } ?? "unknown")")
                }
                Text("Low below \(low)%").foregroundStyle(.secondary)
            case .notFound?:
                Text("Printer not found. Is it on and plugged in?")
            case .busy?:
                Text("The printer is busy. Try again in a moment.")
            case .noReply?:
                Text("The printer did not answer.")
            }
            Button("Refresh") { Task { await refresh() } }
                .disabled(reading == nil)
        }
        .padding(24)
        .frame(minWidth: 320, alignment: .leading)
        .task { await refresh() }
    }

    private func refresh() async {
        reading = nil
        reading = await Task.detached { Printer.readInk() }.value
    }
}
