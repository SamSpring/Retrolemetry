// Compile with AppUpdater.swift, never with the production entry point. This
// harness has its own bundle ID, synthetic defaults and no telemetry/Keychain/login access.
import AppKit
import Combine
import CryptoKit
import Sparkle

@main
@MainActor
enum UpdaterQA {
    static func main() {
        let app = NSApplication.shared
        let delegate = Harness()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
private final class Harness: NSObject, NSApplicationDelegate {
    private var updates: AppUpdater!
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var menu: NSMenu!
    private var clicked = Set<String>()
    private let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "QARoot") as! String)
    private var scenario: String { (try? String(contentsOf: root.appendingPathComponent("scenario"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "invalid" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String }

    private func record(_ event: String, extra: [String: Any] = [:]) {
        var value = extra
        value["event"] = event
        value["build"] = build
        value["scenario"] = scenario
        value["pid"] = ProcessInfo.processInfo.processIdentifier
        value["settingsPreserved"] = UserDefaults.standard.string(forKey: "DockTelemetry.QASentinel") == "synthetic-layout-sentinel"
        if let layout = UserDefaults.standard.dictionary(forKey: "DockTelemetry.QALayout"),
           let data = try? JSONSerialization.data(withJSONObject: layout, options: [.sortedKeys]) {
            value["layoutDigest"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let bytes = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data([10])
        let path = root.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil) }
        let handle = try! FileHandle(forWritingTo: path)
        try! handle.seekToEnd(); try! handle.write(contentsOf: bytes); try! handle.close()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let identity = Bundle.main.bundleIdentifier, identity.hasPrefix("io.github.SamSpring.Retrolemetry.UpdaterQA.") else { fatalError("Not an isolated QA bundle") }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "DockTelemetry.QASentinel") == nil {
            defaults.set("synthetic-layout-sentinel", forKey: "DockTelemetry.QASentinel")
            defaults.set(["module": ["x": 42, "y": 18, "width": 300]], forKey: "DockTelemetry.QALayout")
        }
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let base = Bundle.main.object(forInfoDictionaryKey: "QAFeedBase") as! String
        defaults.set(base + "/" + scenario + ".xml", forKey: "SUFeedURL")
        record("launched", extra: ["layoutPreserved": defaults.dictionary(forKey: "DockTelemetry.QALayout")? ["module"] != nil])
        if build == "2" && scenario == "valid" {
            record("relaunched-new-build")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        updates = AppUpdater(bundleIdentifier: identity)
        updates.start()
        menu = NSMenu(title: "Retrolemetry Updater QA")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "").target = updates.controller
        observation = updates.$lastError.compactMap { $0 }.sink { [weak self] error in
            self?.record("updater-result", extra: ["errorDomain": error.domain, "errorCode": error.code, "description": error.localizedDescription])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            record("manual-check")
            menu.performActionForItem(at: 0)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceNativeUI() }
        }
        RunLoop.main.add(timer!, forMode: .modalPanel)
        RunLoop.main.add(timer!, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [self] in
            record("timeout")
            NSApp.terminate(nil)
        }
    }

    private func advanceNativeUI() {
        if ["tampered", "wrong-key", "wrong-feed"].contains(scenario), let error = updates.lastError {
            record("rejected", extra: ["errorCode": error.code, "errorDomain": error.domain])
            NSApp.terminate(nil)
            return
        }
        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        for window in NSApp.windows where window.isVisible {
            let views = window.contentView.map(walk) ?? []
            let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
            let marker = "window:" + labels
            if !clicked.contains(marker) {
                clicked.insert(marker)
                record("native-window", extra: ["text": labels, "buttons": views.compactMap { ($0 as? NSButton)?.title }])
            }
            if scenario == "no-update" && labels.localizedCaseInsensitiveContains("up to date") {
                record("no-update-visible")
                NSApp.terminate(nil)
                return
            }
            for button in views.compactMap({ $0 as? NSButton }) where button.isEnabled {
                let title = button.title
                if ["Install Update", "Install and Relaunch"].contains(title) && !clicked.contains(title) {
                    clicked.insert(title)
                    record("native-button", extra: ["title": title])
                    button.performClick(nil)
                    return
                }
            }
            if ["tampered", "wrong-key", "wrong-feed"].contains(scenario), labels.contains("Update Error!") {
                if let dismiss = views.compactMap({ $0 as? NSButton }).first(where: { ["Cancel Update", "OK"].contains($0.title) }) {
                    dismiss.performClick(nil)
                    return
                }
            }
        }
    }
}
