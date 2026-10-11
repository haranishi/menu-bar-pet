import Foundation
import MenuBarPetCore

private func statusLineCommand(_ data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let command = (root?["statusLine"] as? [String: Any])?["command"] as? String else {
        let text = String(data: data, encoding: .utf8) ?? "(not utf8)"
        throw AssertionFailure(message: "no statusLine command in \(text)")
    }
    return command
}

private func settings(withStatusLineCommand command: String) -> Data {
    (try? JSONSerialization.data(withJSONObject: [
        "statusLine": ["type": "command", "command": command],
    ])) ?? Data()
}

let aiUsageReviewTests: [TestCase] = [
    TestCase(name: "Installer survives the app moving without wrapping itself twice") {
        let oldCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/old/MenuBarPet")
        let newCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/Applications/MenuBarPet")
        let user = "echo hi"

        let first = ClaudeStatusLineInstaller.install(
            settingsData: settings(withStatusLineCommand: user),
            command: oldCommand
        )
        let second = ClaudeStatusLineInstaller.install(settingsData: first, command: newCommand)
        let command = try statusLineCommand(second)
        try require(command.hasPrefix(newCommand), "the new path must lead: \(command)")
        try require(
            command.components(separatedBy: " --then ").count == 2,
            "only one --then may remain: \(command)"
        )
        try require(ClaudeStatusLineInstaller.wrappedCommand(in: command) == user)
        try require(ClaudeStatusLineInstaller.isInstalled(settingsData: second), "still ours")

        let restored = try statusLineCommand(ClaudeStatusLineInstaller.uninstall(settingsData: second))
        try require(restored == user, "must restore the user's command")

        // 元コマンドが無いまま移動した場合は、解除で statusLine ごと消える。
        let bare = ClaudeStatusLineInstaller.install(settingsData: nil, command: oldCommand)
        let moved = ClaudeStatusLineInstaller.install(settingsData: bare, command: newCommand)
        let movedCommand = try statusLineCommand(moved)
        try require(movedCommand == newCommand, "no --then may appear: \(movedCommand)")
        let cleared = try JSONSerialization.jsonObject(
            with: ClaudeStatusLineInstaller.uninstall(settingsData: moved)
        ) as? [String: Any]
        try require(cleared?["statusLine"] == nil, "statusLine must be gone")

        // 旧実装が作りうる多重ラップも1段に畳み直せる。
        let inner = ClaudeStatusLineInstaller.singleQuoted(user)
        let once = "\(oldCommand) --then \(inner)"
        let doubled = "\(newCommand) --then \(ClaudeStatusLineInstaller.singleQuoted(once))"
        try require(
            ClaudeStatusLineInstaller.innermostCommand(in: doubled) == user,
            "got \(ClaudeStatusLineInstaller.innermostCommand(in: doubled) ?? "nil")"
        )
    },
    TestCase(name: "Installer round trips commands containing quotes and --then") {
        let ourCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/Apps/MenuBarPet")
        let originals = [
            "jq -r '.model.display_name'",
            "printf '%s' \"it's fine\"",
            "echo --then 'nested'",
            "sh -c 'echo hi'",
        ]
        for user in originals {
            let installed = ClaudeStatusLineInstaller.install(
                settingsData: settings(withStatusLineCommand: user),
                command: ourCommand
            )
            let command = try statusLineCommand(installed)
            let unwrapped = ClaudeStatusLineInstaller.wrappedCommand(in: command)
            try require(unwrapped == user, "wrap failed for \(user): \(unwrapped ?? "nil")")

            let restored = try statusLineCommand(
                ClaudeStatusLineInstaller.uninstall(settingsData: installed)
            )
            try require(restored == user, "restore failed for \(user): \(restored)")
        }
    },
    TestCase(name: "A statusLine written as a bare string is inherited, not dropped") {
        let ourCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/Apps/MenuBarPet")
        let installed = ClaudeStatusLineInstaller.install(
            settingsData: Data("{\"statusLine\":\"my-script.sh\",\"model\":\"opus\"}".utf8),
            command: ourCommand
        )
        let command = try statusLineCommand(installed)
        try require(ClaudeStatusLineInstaller.wrappedCommand(in: command) == "my-script.sh")
        let root = try JSONSerialization.jsonObject(with: installed) as? [String: Any]
        try require(root?["model"] as? String == "opus", "other keys must survive")

        let restored = try statusLineCommand(
            ClaudeStatusLineInstaller.uninstall(settingsData: installed)
        )
        try require(restored == "my-script.sh", "the original script must come back")
    },
    TestCase(name: "Reading settings tells a missing file apart from an unreadable one") {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let absent = try ClaudeStatusLineInstaller.readSettings(at: url)
        try require(absent == nil, "missing means nil")

        try Data("{\"model\":\"opus\"}".utf8).write(to: url)
        let present = try ClaudeStatusLineInstaller.readSettings(at: url)
        try require(present != nil)

        guard getuid() != 0 else {
            print("  SKIP: running as root, chmod 000 stays readable")
            return
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
        var threw = false
        do {
            _ = try ClaudeStatusLineInstaller.readSettings(at: url)
        } catch ClaudeSettingsFileError.unreadable {
            threw = true
        }
        try require(threw, "an unreadable file must throw, never look like a missing one")
    },
    TestCase(name: "Epoch values written in milliseconds are understood") {
        let expected = Date(timeIntervalSince1970: 1_789_492_314)
        let snapshot = ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: """
                {"five_hour":{"used_percentage":10,"resets_at":1789492314},\
                "seven_day":{"used_percentage":20,"resets_at":1789492314000}}
                """),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        )
        try require(snapshot?.windows.first?.resetsAt == expected)
        try require(
            snapshot?.windows.last?.resetsAt == expected,
            "milliseconds must not land in the year 58000"
        )
    },
    TestCase(name: "Detail percentages show the effective value with the raw one beside it") {
        let now = referenceNow
        let live = AIUsageWindow(label: "7日", usedPercentage: 41.2, resetsAt: now.addingTimeInterval(60))
        try require(AIUsageAggregator.formatUsedPercentage(live, now: now) == "41%")

        let expired = AIUsageWindow(
            label: "5時間",
            usedPercentage: 88,
            resetsAt: now.addingTimeInterval(-1)
        )
        try require(
            AIUsageAggregator.formatUsedPercentage(expired, now: now) == "0%（リセット済み・元 88%）",
            AIUsageAggregator.formatUsedPercentage(expired, now: now)
        )

        let over = AIUsageWindow(label: "支出上限", usedPercentage: 130, resetsAt: nil)
        try require(AIUsageAggregator.formatUsedPercentage(over, now: now) == "100%（元 130%）")

        // 期限切れでも元が 0% なら括弧を付けない。
        let zero = AIUsageWindow(label: "5時間", usedPercentage: 0, resetsAt: now.addingTimeInterval(-1))
        try require(AIUsageAggregator.formatUsedPercentage(zero, now: now) == "0%")
    },
    TestCase(name: "A fresh rate limit notice drives the pet at one hundred percent") {
        let windows = [
            AIUsageWindow(
                label: "7日",
                usedPercentage: 32,
                resetsAt: referenceNow.addingTimeInterval(3_600)
            ),
        ]
        func snapshot(noteAgeHours: Double) -> AIUsageSnapshot {
            let noteAt = referenceNow.addingTimeInterval(-noteAgeHours * 3_600)
            return AIUsageSnapshot(
                provider: .codex,
                profileName: ".codex-work",
                windows: windows,
                observedAt: referenceNow.addingTimeInterval(-7_200),
                note: "クレジット切れ（workspace_member_credits_depleted）",
                sourcePath: "a",
                extras: [
                    AIUsageSnapshot.rateLimitReachedTypeKey: "workspace_member_credits_depleted",
                    AIUsageSnapshot.noteObservedAtKey: ISO8601DateFormatter().string(from: noteAt),
                ]
            )
        }
        let both = Set(AIUsageProvider.allCases)

        let fresh = snapshot(noteAgeHours: 1)
        try require(
            AIUsageAggregator.driveValue(snapshots: [fresh], enabled: both, now: referenceNow) == 100,
            "a notice from an hour ago must drive at 100"
        )
        let binding = AIUsageAggregator.bindingWindow(
            snapshots: [fresh],
            enabled: both,
            now: referenceNow
        )
        try require(
            binding?.window.label == "上限到達",
            "the headline label must stay readable, got \(binding?.window.label ?? "nil")"
        )

        let stale = snapshot(noteAgeHours: 6)
        try require(
            AIUsageAggregator.driveValue(snapshots: [stale], enabled: both, now: referenceNow) == 32,
            "after five hours the notice is display only"
        )
        try require(AIUsageAggregator.bindingWindow(
            snapshots: [stale],
            enabled: both,
            now: referenceNow
        )?.window.label == "7日")

        // 時計ずれで未来の時刻が入っても「直近の上限到達」にはしない。
        let future = snapshot(noteAgeHours: -1)
        try require(
            AIUsageAggregator.reachedLimitWindow(future, now: referenceNow) == nil,
            "a notice timestamped in the future must not drive"
        )
        try require(
            AIUsageAggregator.driveValue(snapshots: [future], enabled: both, now: referenceNow) == 32,
            "a future notice falls back to the real window"
        )
    },
    TestCase(name: "Codex adoption keeps older windows and the newer notice together") {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let day = home.appendingPathComponent(".codex-work/sessions/2026/09/15")
        try fileManager.createDirectory(at: day, withIntermediateDirectories: true)

        let withWindows = day.appendingPathComponent("rollout-2026-09-15T13-00-00-aaa.jsonl")
        let depleted = day.appendingPathComponent("rollout-2026-09-16T03-00-00-bbb.jsonl")
        try Data((codexWindowsLine + "\n").utf8).write(to: withWindows)
        try Data((codexDepletedLine + "\n").utf8).write(to: depleted)
        // 残高切れのファイルを新しく見せる（mtime 降順が採用順の起点）。
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: depleted.path)
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-600)],
            ofItemAtPath: withWindows.path
        )

        var scanner = CodexSessionScanner()
        let snapshots = scanner.snapshots(homeDirectory: home, fileManager: fileManager)
        try require(snapshots.count == 1, "one snapshot per profile, got \(snapshots.count)")
        guard let snapshot = snapshots.first else { return }
        try require(
            snapshot.windows.map(\.label) == ["5時間", "7日"],
            "windows must survive the newer empty file: \(snapshot.windows.map(\.label))"
        )
        try require(snapshot.note == "クレジット切れ（workspace_member_credits_depleted）")
        try require(snapshot.rateLimitReachedType == "workspace_member_credits_depleted")
        // 枠は古い行の時刻、上限到達は新しい行の時刻。
        try require(
            abs(snapshot.observedAt.timeIntervalSince1970 - 1_789_478_928.436) < 0.01,
            "observedAt was \(snapshot.observedAt)"
        )
        let noteAt = snapshot.noteObservedAt ?? .distantPast
        try require(
            abs(noteAt.timeIntervalSince1970 - 1_789_530_569.337) < 0.01,
            "note time was \(noteAt)"
        )
    },
    TestCase(name: "Codex scanning widens to sixteen files when no window turns up") {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let day = home.appendingPathComponent(".codex-work/sessions/2026/09/16")
        try fileManager.createDirectory(at: day, withIntermediateDirectories: true)

        // 13本の空振り（新しい順）＋14本目に枠。上限に当たった日の実際の並びに合わせてある。
        for index in 0..<13 {
            let url = day.appendingPathComponent(String(format: "rollout-empty-%02d.jsonl", index))
            try Data((codexDepletedLine + "\n").utf8).write(to: url)
            try fileManager.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-Double(index) * 60)],
                ofItemAtPath: url.path
            )
        }
        let deep = day.appendingPathComponent("rollout-deep.jsonl")
        try Data((codexWindowsLine + "\n").utf8).write(to: deep)
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-1_200)],
            ofItemAtPath: deep.path
        )

        var scanner = CodexSessionScanner()
        let snapshots = scanner.snapshots(homeDirectory: home, fileManager: fileManager)
        try require(snapshots.count == 1)
        try require(
            snapshots.first?.windows.map(\.label) == ["5時間", "7日"],
            "the fourteenth file must still be reached: \(snapshots.first?.windows.map(\.label) ?? [])"
        )
        let second = scanner.snapshots(homeDirectory: home, fileManager: fileManager)
        try require(second == snapshots, "cached read must match")
    },
]
