import Foundation
import MenuBarPetCore

/// GUI を立ち上げずに走るモード。`--self-test` と同列の扱いで、`NSApplication` には触れない。
enum AIUsageCLI {
    /// Claude Code の statusLine から呼ばれる。stdin の JSON を保存し、1行を stdout へ返す。
    ///
    /// statusLine を壊さないことが最優先なので、何が起きても exit 0 で戻る。
    static func runStatusLine(arguments: [String]) -> Int32 {
        // 引き継ぎ先のコマンドが stdin を読み切らずに終わると、こちらが SIGPIPE で即死して
        // statusLine が空欄になる（64KB を超える入力で起きる）。落とさずに書き込み失敗として扱う。
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profile = AIUsagePaths.claudeProfileName(environment: environment, homeDirectory: home)

        var snapshot: AIUsageSnapshot?
        if let root = try? JSONSerialization.jsonObject(with: input), root is [String: Any] {
            let store = AIUsageStore.make(environment: environment, homeDirectory: home)
            do {
                try store.write(input, profileName: profile)
            } catch {
                fputs("MenuBarPet: 使用量ファイルを書けませんでした: \(error.localizedDescription)\n", stderr)
            }
            snapshot = ClaudeStatusLineParser.parse(
                input,
                observedAt: Date(),
                profileName: profile,
                sourcePath: AIUsagePaths
                    .claudeUsageFileURL(directory: store.directoryURL, profileName: profile).path
            )
        } else {
            // JSON でないものは素通し保存しない（壊れた入力で前回の値を潰さないため）。
            fputs("MenuBarPet: statusLine の入力が JSON ではありません\n", stderr)
        }

        if let command = value(after: "--then", in: arguments) {
            print(passThrough(command: command, input: input), terminator: "")
        } else {
            print(AIUsageAggregator.formatStatusLine(snapshot))
        }
        return EXIT_SUCCESS
    }

    /// 元々設定されていた statusLine に同じ JSON を渡して、その出力をそのまま返す。
    private static func passThrough(command: String, input: Data) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            fputs("MenuBarPet: --then の実行に失敗しました: \(error.localizedDescription)\n", stderr)
            return "\n"
        }
        // 相手が先に終了していれば EPIPE。握り潰して、そこまでに出た stdout を使う。
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
        let output = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return String(data: output, encoding: .utf8) ?? ""
    }

    /// 実データで受け入れ確認をするための人間可読ダンプ。
    static func runDump() -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = AIUsageStore.make(environment: environment, homeDirectory: home)
        var scanner = CodexSessionScanner()
        let snapshots = store.readClaudeSnapshots() + scanner.snapshots(homeDirectory: home)
        let now = Date()

        print("usage dir: \(store.directoryURL.path)")
        print("home: \(home.path)")
        let kinds: [(kind: AIUsageConfigKind, name: String)] = [(.claude, "claude"), (.codex, "codex")]
        for entry in kinds {
            let found = AIUsagePaths
                .discoverConfigDirectories(entry.kind, in: home, using: .default)
                .map(\.profileName)
            print("\(entry.name) profiles: \(found.isEmpty ? "(none)" : found.joined(separator: ", "))")
        }
        print("")

        for provider in AIUsageProvider.allCases
        where !snapshots.contains(where: { $0.provider == provider }) {
            print("\(provider.displayName): (none)")
        }
        if snapshots.isEmpty { print("(none)") }

        for snapshot in snapshots {
            print("\(snapshot.provider.displayName) / \(snapshot.profileName)")
            if snapshot.windows.isEmpty {
                print("  windows: (none)")
            }
            for window in snapshot.windows {
                let resets = AIUsageAggregator.formatResetsAt(window.resetsAt, now: now)
                print("  \(window.label): \(AIUsageAggregator.formatUsedPercentage(window, now: now))"
                    + "  \(resets.isEmpty ? "(no reset time)" : resets)")
            }
            if let reached = AIUsageAggregator.reachedLimitWindow(snapshot, now: now) {
                print("  \(reached.label): 100% (drives the pet)")
            }
            print("  observedAt: \(ISO8601DateFormatter().string(from: snapshot.observedAt))")
            if let note = snapshot.note { print("  note: \(note)") }
            if !snapshot.extras.isEmpty {
                let extras = snapshot.extras.keys.sorted().map { "\($0)=\(snapshot.extras[$0] ?? "")" }
                print("  extras: \(extras.joined(separator: " "))")
            }
            print("  sourcePath: \(snapshot.sourcePath)")
        }

        let enabled = Set(AIUsageProvider.allCases)
        if let drive = AIUsageAggregator.driveValue(snapshots: snapshots, enabled: enabled, now: now),
           let binding = AIUsageAggregator.bindingWindow(snapshots: snapshots, enabled: enabled, now: now) {
            print("")
            print(String(
                format: "driveValue: %.1f%% (%@ %@ / %@)",
                drive,
                binding.snapshot.provider.displayName,
                binding.window.label,
                binding.snapshot.profileName
            ))
        }

        print("")
        print("menubar:")
        for row in MenuBarReadout.rows(snapshots: snapshots, enabled: enabled, now: now) {
            print("  \(row)")
        }
        return EXIT_SUCCESS
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else { return nil }
        let value = arguments[index + 1]
        return value.isEmpty ? nil : value
    }
}
