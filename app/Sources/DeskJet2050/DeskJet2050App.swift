import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        #if DEBUG
        // `DeskJet2050 --snapshot file.png` saves the window with sample levels, to check the layout
        // without the printer. Add -AppleLanguages "(pt-BR)" for another language, --not-installed for the
        // driver missing, --settings for the Settings window.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.save(to: CommandLine.arguments[i + 1]) }
            return
        }
        // `DeskJet2050 --prepare-driver` only copies the driver folder, without opening Terminal.
        if CommandLine.arguments.contains("--prepare-driver") {
            MainActor.assumeIsolated {
                do { print(try DriverModel().prepareDriverFolder().path) } catch { print(error) }
            }
            return
        }
        #endif
        DeskJet2050App.main()
    }
}

struct DeskJet2050App: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = InkModel()
    @State private var driver = DriverModel()
    @AppStorage(AppSettings.showInMenuBar) private var showInMenuBar = false

    var body: some Scene {
        Window("DeskJet 2050", id: "main") {
            InkView(model: model, driver: driver)
                .task {
                    await driver.check()
                    await model.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task {
                        await driver.check()
                        await model.refreshIfOld()
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.needsAttention ? "drop.triangle.fill" : "printer.fill")
                .accessibilityLabel(Text(verbatim: "DeskJet 2050"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(driver: driver)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window quits the app, unless the menu bar icon is on: then the app stays there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: AppSettings.showInMenuBar)
    }
}

#if DEBUG
@MainActor
enum Snapshot {
    /// Draws the real window (AppKit controls included) off screen and saves it as PNG.
    static func save(to path: String) {
        _ = NSApplication.shared
        let sample = InkModel(sample: .levels([
            Cartridge(label: "CMY", name: "Tri-color", state: "newGenuineHP", level: 62),
            Cartridge(label: "K", name: "Black", state: "newGenuineHP", level: 20),
        ], lowThreshold: 20))
        let installed = CommandLine.arguments.contains("--not-installed") ? DriverModel.Status.notInstalled : .installed
        let driver = DriverModel(sample: installed)
        let root = CommandLine.arguments.contains("--settings")
            ? AnyView(SettingsView(driver: driver)) : AnyView(InkView(model: sample, driver: driver))
        let host = NSHostingView(rootView: root)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("Could not render")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Saved \(path)")
    }
}
#endif
