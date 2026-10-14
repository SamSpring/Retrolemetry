import AppKit
import Sparkle

/// Sparkle owns download, verification, installation and relaunch. Never implement
/// a second installer, trust override, or credential store here.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )
    @Published private(set) var available = false
    @Published private(set) var canCheck = false
    @Published private(set) var lastError: NSError?
    private var checkObservation: NSKeyValueObservation?
    private var automaticObservation: NSKeyValueObservation?
    private let bundleIdentifier: String

    init(bundleIdentifier: String = UpdateConfiguration.bundleIdentifier) {
        self.bundleIdentifier = bundleIdentifier
        super.init()
    }

    func start() {
        // A source-run executable or unit test is not an updatable .app bundle.
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == bundleIdentifier,
              UpdateConfiguration.isValid(Bundle.main.infoDictionary ?? [:]) else { return }
        guard !available else { return }
        checkObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let enabled = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = enabled }
        }
        automaticObservation = controller.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        controller.startUpdater()
        available = true
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Layouts and display settings already use the existing defaults domain.
        // Flush pending edits before Sparkle replaces the app, without resetting it.
        UserDefaults.standard.synchronize()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        lastError = error as NSError
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}

enum UpdateConfiguration {
    static let bundleIdentifier = "io.github.SamSpring.Retrolemetry"
    static let feedURL = "https://samspring.github.io/Retrolemetry/appcast.xml"

    static func isValid(_ info: [String: Any]) -> Bool {
        guard info["SUFeedURL"] as? String == feedURL,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true,
              (info["SUSignedFeedFailureExpirationInterval"] as? NSNumber)?.doubleValue == 0 else { return false }
        return true
    }
}
