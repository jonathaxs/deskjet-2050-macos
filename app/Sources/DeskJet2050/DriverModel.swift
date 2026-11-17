import AppKit
import Observation

/// Whether the driver is installed, and installing or removing it through Terminal.
///
/// The app never asks for the password. It copies the driver folder it carries to Application Support
/// and opens Install.command or Uninstall.command there in Terminal, where the person types the
/// password for sudo, exactly as when they double-click the file themselves.
@MainActor
@Observable
final class DriverModel {
    enum Status: Equatable {
        case checking
        case installed
        case noQueue        // driver files are there, the printer queue is not
        case notInstalled
    }

    private(set) var status: Status = .checking
    /// True while Terminal is running the installer or uninstaller and we are watching for the result.
    private(set) var waitingForTerminal = false
    private(set) var error: String?
    /// What Install.command needs before it can build the driver (nil while checking).
    private(set) var hasCommandLineTools: Bool?
    private(set) var hasHomebrew: Bool?

    nonisolated static let installDir = "/Library/Printers/DeskJet2050"
    nonisolated static let ppd = "/Library/Printers/PPDs/Contents/Resources/deskjet2050-j510-hpcups.ppd"
    nonisolated static let queue = "Deskjet_2050"

    private var watchTask: Task<Void, Never>?
    /// When the filter was last written; a reinstall changes it even though the status stays "installed".
    private var filterDate: Date?

    init() {}

    init(sample: Status, homebrew: Bool = true) {
        status = sample
        hasCommandLineTools = true
        hasHomebrew = homebrew
    }

    func check() async {
        let (status, date, tools, brew) = await Task.detached {
            (Self.currentStatus(), Self.currentFilterDate(), Self.commandLineToolsInstalled(), Self.homebrewInstalled())
        }.value
        self.status = status
        filterDate = date
        hasCommandLineTools = tools
        hasHomebrew = brew
    }

    /// `xcode-select -p` only prints a path when the Command Line Tools (or Xcode) are there.
    nonisolated static func commandLineToolsInstalled() -> Bool {
        run("/usr/bin/xcode-select", ["-p"])
    }

    /// Same places Install.command looks when brew is not in the PATH.
    nonisolated static func homebrewInstalled() -> Bool {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func currentFilterDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: installDir + "/Filter/hpcups")
        return attributes?[.modificationDate] as? Date
    }

    nonisolated static func currentStatus() -> Status {
        let fm = FileManager.default
        let files = [installDir + "/Filter/hpcups", installDir + "/Filter/deskjet2050", ppd]
        guard files.allSatisfy({ fm.fileExists(atPath: $0) }) else {
            return .notInstalled
        }
        return queueExists() ? .installed : .noQueue
    }

    nonisolated private static func queueExists() -> Bool {
        run("/usr/bin/lpstat", ["-p", queue])
    }

    /// Runs a command quietly; true when it exits with 0.
    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    func install() { runInTerminal("Install.command") }
    func uninstall() { runInTerminal("Uninstall.command") }

    private func runInTerminal(_ script: String) {
        error = nil
        do {
            let folder = try prepareDriverFolder()
            let file = folder.appendingPathComponent(script)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([file], withApplicationAt: terminal,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in self.error = error.localizedDescription }
                }
            }
            watch()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Copies the driver folder from the app to ~/Library/Application Support/DeskJet2050/driver.
    /// Keeps files/build and files/downloads from earlier runs, so a reinstall does not download HPLIP again.
    func prepareDriverFolder() throws -> URL {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "driver", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        let target = support.appendingPathComponent("DeskJet2050/driver", isDirectory: true)
        try fm.createDirectory(at: target.appendingPathComponent("files"), withIntermediateDirectories: true)

        func replace(_ relative: String) throws {
            let from = source.appendingPathComponent(relative)
            let to = target.appendingPathComponent(relative)
            if fm.fileExists(atPath: to.path) {
                try fm.removeItem(at: to)
            }
            try fm.copyItem(at: from, to: to)
        }
        for item in try fm.contentsOfDirectory(atPath: source.path) where item != "files" {
            try replace(item)
        }
        let keep: Set = ["build", "downloads"]
        for item in try fm.contentsOfDirectory(atPath: source.appendingPathComponent("files").path)
        where !keep.contains(item) {
            try replace("files/" + item)
        }

        // If the app came from a download, its files carry the quarantine flag and the copies would too;
        // Terminal would then refuse to open Install.command. The copies are ours, so clear it.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", target.path]
        xattr.standardError = FileHandle.nullDevice
        try? xattr.run()
        xattr.waitUntilExit()
        return target
    }

    /// Checks the status every few seconds until it changes or 15 minutes pass.
    private func watch() {
        watchTask?.cancel()
        let before = status
        let beforeDate = filterDate
        waitingForTerminal = true
        watchTask = Task {
            for _ in 0..<300 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                await check()
                if status != before || filterDate != beforeDate { break }
            }
            waitingForTerminal = false
        }
    }

    /// Stops waiting (the person closed Terminal without finishing, for example).
    func stopWaiting() {
        watchTask?.cancel()
        waitingForTerminal = false
    }
}
