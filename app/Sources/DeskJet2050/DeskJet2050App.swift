import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        #if DEBUG
        // `DeskJet2050 --snapshot file.png` saves the window with sample levels, to check the layout
        // without the printer. Add -AppleLanguages "(pt-BR)" to see it in Portuguese.
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

    var body: some Scene {
        Window("DeskJet 2050", id: "main") {
            InkView(model: model)
                .task { await model.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.refreshIfOld() }
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

#if DEBUG
@MainActor
enum Snapshot {
    static func save(to path: String) {
        let sample = InkModel(sample: .levels([
            Cartridge(label: "CMY", name: "Tri-color", state: "newGenuineHP", level: 62),
            Cartridge(label: "K", name: "Black", state: "newGenuineHP", level: 20),
        ], lowThreshold: 20))
        let view = InkView(model: sample).background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("Could not render")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Saved \(path)")
    }
}
#endif
