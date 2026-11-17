import AppKit
import SwiftUI

/// Main window, laid out like System Settings. Settings open as a page in the same window, with Back.
struct InkView: View {
    @Bindable var model: InkModel
    let driver: DriverModel
    @State private var showSettings = false
    @State private var confirmUninstall = false

    var body: some View {
        NavigationStack {
            MainPage(model: model, driver: driver, showSettings: $showSettings) { confirmUninstall = true }
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView(driver: driver) { confirmUninstall = true }
                }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in showSettings = true }
        #if DEBUG
        // `--open-settings` starts on the Settings page, to check it without clicking.
        .onAppear { if CommandLine.arguments.contains("--open-settings") { showSettings = true } }
        #endif
        .confirmationDialog("Uninstall the driver?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { driver.uninstall() }
        } message: {
            Text("This removes the driver and the printer queue. You can install it again later.")
        }
    }
}

/// First page: the printer with Refresh and Settings under it, the ink, and help when something is missing.
struct MainPage: View {
    let model: InkModel
    let driver: DriverModel
    @Binding var showSettings: Bool
    let requestUninstall: () -> Void

    var body: some View {
        Form {
            Section {
                PrinterRow(model: model)
                if let hint = model.problemHint {
                    Label(hint, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack(spacing: 12) {
                    Button("Refresh") {
                        Task { await model.refresh() }
                    }
                    .keyboardShortcut("r")
                    .disabled(model.isReading)
                    Button("Settings") { showSettings = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }

            // Always on screen, so the window keeps its size. Without a reading the bars are just grey.
            let shown = model.shownLevels
            Section {
                if let shown, shown.cartridges.isEmpty {
                    Text("No cartridges reported").foregroundStyle(.secondary)
                }
                ForEach(shown?.cartridges ?? InkModel.placeholder) { cartridge in
                    CartridgeRow(cartridge: cartridge, lowThreshold: shown?.lowThreshold ?? 20,
                                 showsDetails: shown != nil)
                }
            } header: {
                Text("Ink")
            } footer: {
                Text("Estimates from the printer. It warns when a cartridge reaches \(shown?.lowThreshold ?? 20)%.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .notFound = model.status {
                NotFoundHelp()
            }

            // Reinstall and Uninstall live in Settings; the main window only offers Install when it is needed.
            if driver.status == .notInstalled || driver.status == .noQueue {
                DriverSection(driver: driver, requestUninstall: requestUninstall)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("DeskJet 2050")
        .navigationSubtitle(subtitle)
        .hiddenToolbarLine()
    }

    private var subtitle: Text {
        if let date = model.lastUpdate {
            Text("Updated at \(date, style: .time)")
        } else {
            Text(verbatim: "")
        }
    }
}

extension View {
    /// Hides the line under the title bar, which sits right under the "Updated at" subtitle.
    @ViewBuilder
    func hiddenToolbarLine() -> some View {
        if #available(macOS 15, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}

extension Notification.Name {
    /// Sent by the app menu's Settings… item (⌘,) to open the Settings page.
    static let showSettings = Notification.Name("showSettings")
}

/// Settings page (Settings button or ⌘,): the driver and the menu bar option. Back is in the title bar.
struct SettingsView: View {
    let driver: DriverModel
    let requestUninstall: () -> Void
    @AppStorage(AppSettings.showInMenuBar) private var showInMenuBar = false

    var body: some View {
        Form {
            DriverSection(driver: driver, requestUninstall: requestUninstall)
            Section {
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in the menu bar")
                    Text("Shows the ink levels next to the clock.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Settings")
        .hiddenToolbarLine()
        .task { await driver.check() }
    }
}

/// Driver state with Install, Reinstall and Uninstall. The work happens in Terminal.
struct DriverSection: View {
    let driver: DriverModel
    let requestUninstall: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Printer driver")
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(statusText).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Spacer()
                buttons
            }
            .padding(.vertical, 2)
            if driver.status == .notInstalled || driver.status == .noQueue {
                RequirementRow(title: "Command Line Tools", ok: driver.hasCommandLineTools,
                               missing: "Apple’s developer tools. The installer opens the window to get them.")
                RequirementRow(title: "Homebrew", ok: driver.hasHomebrew,
                               missing: "Needed to build the driver. Install it, then come back here.") {
                    Link("Open brew.sh", destination: URL(string: "https://brew.sh")!)
                }
            }
            if driver.waitingForTerminal {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Terminal…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop waiting") { driver.stopWaiting() }
                        .buttonStyle(.link)
                }
                .font(.subheadline)
            }
            if let error = driver.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        } header: {
            Text("Driver")
        } footer: {
            Text("Terminal opens to finish. Type your Mac password there: this app never sees it.")
                .foregroundStyle(.secondary)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch driver.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled, .noQueue:
            Button("Install…") { driver.install() }
                .buttonStyle(.borderedProminent)
                .disabled(driver.waitingForTerminal)
        case .installed:
            HStack {
                Button("Reinstall…") { driver.install() }
                Button("Uninstall…") { requestUninstall() }
            }
            .disabled(driver.waitingForTerminal)
        }
    }

    private var statusText: LocalizedStringKey {
        switch driver.status {
        case .checking: "Checking…"
        case .installed: "Installed"
        case .noQueue: "Installed, but the printer queue is missing"
        case .notInstalled: "Not installed"
        }
    }

    private var color: Color {
        switch driver.status {
        case .checking: .gray
        case .installed: .green
        case .noQueue: .orange
        case .notInstalled: .red
        }
    }
}

/// One thing the installer needs, with a check mark or what to do about it.
struct RequirementRow<Action: View>: View {
    let title: LocalizedStringKey
    let ok: Bool?
    let missing: LocalizedStringKey
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch ok {
                case nil: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case false?: Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if ok == false {
                    Text(missing).foregroundStyle(.secondary).font(.subheadline)
                }
            }
            Spacer()
            if ok == false { action() }
        }
    }
}

extension RequirementRow where Action == EmptyView {
    init(title: LocalizedStringKey, ok: Bool?, missing: LocalizedStringKey) {
        self.init(title: title, ok: ok, missing: missing) { EmptyView() }
    }
}

/// Steps for when the Mac does not see the printer, including the USB accessory permission.
struct NotFoundHelp: View {
    static let securitySettings = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security")!

    var body: some View {
        Section {
            step(1, "Turn the printer on and plug it into the Mac with the USB cable.")
            step(2, "If the Mac asks whether to allow the accessory, click Allow. If you clicked Don’t Allow, unplug the cable and plug it in again.")
            HStack(alignment: .firstTextBaseline) {
                step(3, "Still not found? In Privacy & Security, check “Allow accessories to connect”.")
                Spacer()
                Button("Open…") { NSWorkspace.shared.open(Self.securitySettings) }
                    .help(Text("Opens Privacy & Security in System Settings"))
            }
        } header: {
            Text("Can’t find the printer?")
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(n).circle.fill").foregroundStyle(.secondary)
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
    /// False while there is no reading: only the name and a grey bar, same height as a real row.
    var showsDetails = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(cartridge.displayName)
                origin
                Spacer()
                Text(verbatim: cartridge.level.map { "\($0)%" } ?? "–")
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            InkBar(level: cartridge.level, lowThreshold: lowThreshold, fill: cartridge.fill, showsMark: showsDetails)
            state
                .opacity(showsDetails ? 1 : 0)
                .accessibilityHidden(!showsDetails)
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
    var showsMark = true
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
                if showsMark {
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1.5, height: geo.size.height + 6)
                        .offset(x: width * CGFloat(lowThreshold) / 100)
                }
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
