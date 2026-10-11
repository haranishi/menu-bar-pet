import AppKit
import MenuBarPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var model: PetViewModel?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let aiUsage = AIUsageRepository()
        let model = PetViewModel(
            cpuSampler: SystemCPUSampler(),
            settingsStore: UserDefaultsSettingsStore(),
            aiUsage: aiUsage
        )
        self.model = model
        statusController = StatusItemController(model: model, aiUsage: aiUsage)
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
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--benchmark") {
            let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : "2000"
            guard let iterations = Int(value), (1...100_000).contains(iterations) else {
                fputs("--benchmark の反復数は1〜100000で指定してください。\n", stderr)
                exit(EXIT_FAILURE)
            }
            PerformanceBenchmark.run(iterations: iterations)
            exit(EXIT_SUCCESS)
        }
        if arguments.contains("--render-self-test") {
            exit(RenderingSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if arguments.contains("--self-test") {
            exit(DomainSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if arguments.contains("--statusline") {
            exit(AIUsageCLI.runStatusLine(arguments: arguments))
        }
        if arguments.contains("--ai-usage-dump") {
            exit(AIUsageCLI.runDump())
        }
        if let flagIndex = arguments.firstIndex(of: "--menubar-snapshot") {
            guard arguments.indices.contains(flagIndex + 1) else {
                fputs("--menubar-snapshot の後に出力ディレクトリを指定してください。\n", stderr)
                exit(EXIT_FAILURE)
            }
            do {
                try MenuBarSnapshotExporter.export(
                    to: URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
                )
                exit(EXIT_SUCCESS)
            } catch {
                fputs("メニューバーの書き出しに失敗しました: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        if let flagIndex = arguments.firstIndex(of: "--filmstrip") {
            guard arguments.indices.contains(flagIndex + 1) else {
                fputs("\(FilmstripExportError.missingOutputDirectory.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            do {
                let outputURL = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
                try FilmstripExporter.export(to: outputURL)
                print("Exported filmstrips to \(outputURL.path)")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Filmstrip export failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
