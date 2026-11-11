import SwiftUI

/// Main window, laid out like System Settings: the printer, its cartridges, and the app options.
struct InkView: View {
    @Bindable var model: InkModel
    @AppStorage(Settings.showInMenuBar) private var showInMenuBar = false

    var body: some View {
        Form {
            Section {
                PrinterRow(model: model)
                if let hint = model.problemHint {
                    Label(hint, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let last = model.lastLevels {
                Section {
                    if last.cartridges.isEmpty {
                        Text("No cartridges reported").foregroundStyle(.secondary)
                    }
                    ForEach(last.cartridges) { cartridge in
                        CartridgeRow(cartridge: cartridge, lowThreshold: last.lowThreshold)
                    }
                } header: {
                    Text("Ink")
                } footer: {
                    Text("Estimates from the printer. It warns when a cartridge reaches \(last.lowThreshold)%.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in the menu bar")
                    Text("Shows the ink levels next to the clock.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("DeskJet 2050")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help(Text("Refresh"))
                .keyboardShortcut("r")
                .disabled(model.isReading)
            }
        }
    }

    private var subtitle: Text {
        if let date = model.lastUpdate {
            Text("Updated at \(date, style: .time)")
        } else {
            Text(verbatim: "")
        }
    }
}

/// Printer icon, name and connection state.
struct PrinterRow: View {
    let model: InkModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.gray.gradient, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "HP Deskjet 2050").font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(model.statusColor).frame(width: 7, height: 7)
                    Text(model.statusText).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            Spacer()
            if model.isReading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One cartridge: name, percent, a bar with the "low" mark, and its state.
struct CartridgeRow: View {
    let cartridge: Cartridge
    let lowThreshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(cartridge.displayName)
                origin
                Spacer()
                Text(verbatim: cartridge.level.map { "\($0)%" } ?? "–")
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            InkBar(level: cartridge.level, lowThreshold: lowThreshold, fill: cartridge.fill)
            state
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var origin: some View {
        switch cartridge.origin {
        case .genuine: badge("Genuine HP", "checkmark.seal.fill", .blue)
        case .refilled: badge("Refilled HP", "arrow.triangle.2.circlepath", .secondary)
        case .notHP: badge("Not HP", "seal", .secondary)
        case .missing, .unknown: EmptyView()
        }
    }

    private func badge(_ text: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var state: some View {
        let (text, icon, color) = cartridge.stateInfo(lowThreshold: lowThreshold)
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .font(.subheadline)
    }
}

/// Horizontal bar with a small mark where the printer starts calling the ink low.
struct InkBar: View {
    let level: Int?
    let lowThreshold: Int
    let fill: AnyShapeStyle
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat(min(max(level ?? 0, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fill)
                    .frame(width: max(fraction > 0 ? height : 0, width * fraction))
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1.5, height: geo.size.height + 6)
                    .offset(x: width * CGFloat(lowThreshold) / 100)
            }
        }
        .frame(height: height)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared by the window and the menu bar

extension Cartridge {
    var displayName: LocalizedStringKey {
        switch label {
        case "K": "Black"
        case "CMY": "Tri-color"
        case "C": "Cyan"
        case "M": "Magenta"
        case "Y": "Yellow"
        default: LocalizedStringKey(name)
        }
    }

    var fill: AnyShapeStyle {
        let magenta = Color(red: 0.93, green: 0.2, blue: 0.6)
        switch label {
        case "K": return AnyShapeStyle(Color.primary.opacity(0.85))
        case "CMY":
            return AnyShapeStyle(LinearGradient(colors: [.cyan, magenta, .yellow],
                                                startPoint: .leading, endPoint: .trailing))
        case "C": return AnyShapeStyle(Color.cyan)
        case "M": return AnyShapeStyle(magenta)
        case "Y": return AnyShapeStyle(Color.yellow)
        default: return AnyShapeStyle(Color.accentColor)
        }
    }

    func isLow(_ lowThreshold: Int) -> Bool {
        origin == .missing || (level.map { $0 <= lowThreshold } ?? false)
    }

    func stateInfo(lowThreshold: Int) -> (LocalizedStringKey, String, Color) {
        if origin == .missing { return ("Cartridge missing", "xmark.circle.fill", .red) }
        guard let level else { return ("Unknown level", "questionmark.circle", .secondary) }
        if level == 0 { return ("Empty", "xmark.circle.fill", .red) }
        if level <= lowThreshold { return ("Low ink", "exclamationmark.triangle.fill", .orange) }
        return ("OK", "checkmark.circle.fill", .green)
    }
}

extension InkModel {
    var statusText: LocalizedStringKey {
        switch status {
        case .loading: "Reading the printer…"
        case .levels: "Connected over USB"
        case .notFound: "Printer not found"
        case .busy: "The printer is busy"
        case .noReply: "The printer did not answer"
        }
    }

    var statusColor: Color {
        switch status {
        case .loading: .gray
        case .levels: .green
        case .notFound, .noReply: .red
        case .busy: .orange
        }
    }

    /// What to do when the printer could not be read.
    var problemHint: LocalizedStringKey? {
        switch status {
        case .notFound: "Turn the printer on and plug it into the Mac with the USB cable."
        case .busy: "It is probably printing. Try again in a moment."
        case .noReply: "Turn it off and on again, then refresh."
        default: nil
        }
    }

    /// True when any cartridge is low, empty or missing (the menu bar icon shows a warning).
    var needsAttention: Bool {
        guard let last = lastLevels else { return false }
        return last.cartridges.contains { $0.isLow(last.lowThreshold) }
    }
}
