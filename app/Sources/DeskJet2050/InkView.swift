import SwiftUI

/// Main window: the printer and how much ink each cartridge has.
struct InkView: View {
    @Bindable var model: InkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
            footer
        }
        .padding(24)
        .frame(width: 440)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "HP Deskjet 2050")
                    .font(.title2.weight(.semibold))
                Label {
                    Text(statusText)
                } icon: {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusText: LocalizedStringKey {
        switch model.status {
        case .loading: "Reading the printer…"
        case .levels: "Connected over USB"
        case .notFound: "Printer not found"
        case .busy: "The printer is busy"
        case .noReply: "The printer did not answer"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .loading: .gray
        case .levels: .green
        case .notFound, .noReply: .red
        case .busy: .orange
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let last = model.lastLevels {
            VStack(spacing: 12) {
                if last.cartridges.isEmpty {
                    Text("No cartridges reported").foregroundStyle(.secondary)
                }
                ForEach(last.cartridges) { cartridge in
                    CartridgeRow(cartridge: cartridge, lowThreshold: last.lowThreshold)
                }
            }
            if let hint = problemHint {
                hintBox(hint)
            }
        } else if case .loading = model.status {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(height: 120)
        } else if let hint = problemHint {
            hintBox(hint)
        }
    }

    /// What to do when the printer could not be read.
    private var problemHint: LocalizedStringKey? {
        switch model.status {
        case .notFound: "Turn the printer on and plug it into the Mac with the USB cable."
        case .busy: "It is probably printing. Try again in a moment."
        case .noReply: "Turn it off and on again, then refresh."
        default: nil
        }
    }

    private func hintBox(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let low = model.lastLevels?.lowThreshold {
                Text("Estimates from the printer. It warns when a cartridge reaches \(low)%.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let date = model.lastUpdate {
                    Text("Updated at \(date, style: .time)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isReading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(model.isReading)
            }
        }
    }
}

/// One cartridge: name, percent, a bar with the "low" mark, and its state.
struct CartridgeRow: View {
    let cartridge: Cartridge
    let lowThreshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                origin
                Spacer()
                Text(verbatim: cartridge.level.map { "\($0)%" } ?? "–")
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            InkBar(level: cartridge.level, lowThreshold: lowThreshold, fill: fill)
            state
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var name: LocalizedStringKey {
        switch cartridge.label {
        case "K": "Black"
        case "CMY": "Tri-color"
        case "C": "Cyan"
        case "M": "Magenta"
        case "Y": "Yellow"
        default: LocalizedStringKey(cartridge.name)
        }
    }

    private var fill: AnyShapeStyle {
        switch cartridge.label {
        case "K": AnyShapeStyle(Color.primary.opacity(0.85))
        case "CMY":
            AnyShapeStyle(LinearGradient(colors: [.cyan, Color(red: 0.93, green: 0.2, blue: 0.6), .yellow],
                                         startPoint: .leading, endPoint: .trailing))
        case "C": AnyShapeStyle(Color.cyan)
        case "M": AnyShapeStyle(Color(red: 0.93, green: 0.2, blue: 0.6))
        case "Y": AnyShapeStyle(Color.yellow)
        default: AnyShapeStyle(Color.accentColor)
        }
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
            .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var state: some View {
        if cartridge.origin == .missing {
            stateLabel("Cartridge missing", "xmark.circle.fill", .red)
        } else if let level = cartridge.level {
            if level == 0 {
                stateLabel("Empty", "xmark.circle.fill", .red)
            } else if level <= lowThreshold {
                stateLabel("Low ink", "exclamationmark.triangle.fill", .orange)
            } else {
                stateLabel("OK", "checkmark.circle.fill", .green)
            }
        } else {
            stateLabel("Unknown level", "questionmark.circle", .secondary)
        }
    }

    private func stateLabel(_ text: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
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

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat(min(max(level ?? 0, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fill)
                    .frame(width: max(fraction > 0 ? 8 : 0, width * fraction))
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1.5, height: geo.size.height + 6)
                    .offset(x: width * CGFloat(lowThreshold) / 100)
            }
        }
        .frame(height: 10)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}
