import AppKit
import SwiftUI

enum Settings {
    /// UserDefaults key: show the optional icon in the menu bar (off by default).
    static let showInMenuBar = "showInMenuBar"
}

/// Small panel that opens from the menu bar icon.
struct MenuBarView: View {
    let model: InkModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(model.statusColor).frame(width: 7, height: 7)
                Text(verbatim: "HP Deskjet 2050").font(.headline)
                Spacer()
                if model.isReading {
                    ProgressView().controlSize(.mini)
                }
            }

            if let last = model.lastLevels {
                ForEach(last.cartridges) { cartridge in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(cartridge.displayName)
                            Spacer()
                            Text(verbatim: cartridge.level.map { "\($0)%" } ?? "–")
                                .monospacedDigit()
                                .foregroundStyle(cartridge.isLow(last.lowThreshold) ? .orange : .primary)
                        }
                        .font(.subheadline)
                        InkBar(level: cartridge.level, lowThreshold: last.lowThreshold,
                               fill: cartridge.fill, height: 6)
                    }
                }
            } else {
                Text(model.statusText).foregroundStyle(.secondary).font(.subheadline)
            }

            Divider()

            HStack {
                Button("Open DeskJet 2050") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Text("Refresh"))
                .disabled(model.isReading)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help(Text("Quit"))
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 260)
        .task { await model.refreshIfOld() }
    }
}
