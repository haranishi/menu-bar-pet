import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var model: PetViewModel?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PetViewModel(
            cpuSampler: SystemCPUSampler(),
            settingsStore: UserDefaultsSettingsStore(),
            imageStore: LocalPetImageStore()
        )
        self.model = model
        statusController = StatusItemController(model: model)
        model.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            Task { @MainActor in model?.handleWake() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}

@main
enum MenuBarPetMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(DomainSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
