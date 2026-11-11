import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        #if DEBUG
        // `DeskJet2050 --snapshot file.png` saves the window with sample levels, to check the layout
        // without the printer. Add -AppleLanguages "(pt-BR)" for another language.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.save(to: CommandLine.arguments[i + 1]) }
            return
        }
        #endif
        DeskJet2050App.main()
    }
}

struct DeskJet2050App: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = InkModel()
    @AppStorage(Settings.showInMenuBar) private var showInMenuBar = false

    var body: some Scene {
        Window("DeskJet 2050", id: "main") {
            InkView(model: model)
                .task { await model.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.refreshIfOld() }
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window quits the app, unless the menu bar icon is on: then the app stays there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Settings.showInMenuBar)
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
        let host = NSHostingView(rootView: InkView(model: sample))
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
