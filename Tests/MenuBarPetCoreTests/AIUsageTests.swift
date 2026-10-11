import Foundation
import MenuBarPetCore

let referenceNow = Date(timeIntervalSince1970: 1_789_400_000)

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

func claudeFixture(rateLimits: String?, extras: Bool = true) -> Data {
    var parts: [String] = ["\"session_id\":\"abc\"", "\"version\":\"2.1.90\""]
    if extras {
        parts.append("\"model\":{\"id\":\"claude-opus-5\",\"display_name\":\"Opus\"}")
        parts.append("\"context_window\":{\"used_percentage\":8,\"remaining_percentage\":92}")
        parts.append("\"cost\":{\"total_cost_usd\":0.01234,\"total_duration_ms\":45000}")
    }
    if let rateLimits { parts.append("\"rate_limits\":\(rateLimits)") }
    return Data("{\(parts.joined(separator: ","))}".utf8)
}

// REQ 1-3 に載っている実データ2行（2026-09-15 の枠あり／2026-09-16 の残高切れ）。
let codexWindowsLine = """
{"timestamp":"2026-09-15T13:28:48.436Z","ordinal":16,"type":"event_msg","payload":{"type":"token_count",\
"info":{"total_token_usage":{"input_tokens":18548,"cached_input_tokens":12032,"cache_write_input_tokens":0,\
"output_tokens":155,"reasoning_output_tokens":0,"total_tokens":18703},"last_token_usage":{"input_tokens":18548,\
"cached_input_tokens":12032,"cache_write_input_tokens":0,"output_tokens":155,"reasoning_output_tokens":0,\
"total_tokens":18703},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,\
"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1789492314},\
"secondary":{"used_percent":88.0,"window_minutes":10080,"resets_at":1789805930},\
"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,\
"spend_control_reached":null,"plan_type":"team","rate_limit_reached_type":null}}}
"""

let codexDepletedLine = """
{"timestamp":"2026-09-16T03:49:29.337Z","ordinal":10,"type":"event_msg","payload":{"type":"token_count",\
"info":null,"rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,\
"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,\
"spend_control_reached":null,"plan_type":null,"rate_limit_reached_type":"workspace_member_credits_depleted"}}}
"""

func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("menubarpet-aiusage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let aiUsageTests: [TestCase] = [
    TestCase(name: "statusLine JSON parses both rate limit windows") {
        let data = claudeFixture(rateLimits: """
            {"five_hour":{"used_percentage":23.5,"resets_at":1738425600},\
            "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}
            """)
        let snapshot = ClaudeStatusLineParser.parse(
            data,
            observedAt: referenceNow,
            profileName: ".claude-work",
            sourcePath: "/tmp/claude-.claude-work.json"
        )
        try require(snapshot != nil, "expected a snapshot")
        guard let snapshot else { return }
        try require(snapshot.provider == .claudeCode)
        try require(snapshot.profileName == ".claude-work")
        try require(snapshot.windows.map(\.label) == ["5時間", "7日"])
        try require(abs(snapshot.windows[0].usedPercentage - 23.5) < 1e-9)
        try require(abs(snapshot.windows[1].usedPercentage - 41.2) < 1e-9)
        try require(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        try require(snapshot.observedAt == referenceNow)
        try require(snapshot.note == nil)
    },
    TestCase(name: "statusLine JSON without rate_limits yields no snapshot") {
        try require(ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: nil),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        ) == nil, "missing rate_limits must be nil")
        try require(ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: "{}"),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        ) == nil, "empty rate_limits must be nil")
        try require(ClaudeStatusLineParser.parse(
            Data("not json".utf8),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        ) == nil, "garbage input must be nil")
    },
    TestCase(name: "statusLine JSON tolerates a missing window and keeps spend_limit") {
        let snapshot = ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: """
                {"seven_day":{"used_percentage":41.2},\
                "spend_limit":{"used_percentage":120.5,"resets_at":1740787200}}
                """),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        )
        try require(snapshot?.windows.map(\.label) == ["7日", "支出上限"])
        try require(snapshot?.windows.first?.resetsAt == nil, "resets_at may be absent")
        try require(abs((snapshot?.windows.last?.usedPercentage ?? 0) - 120.5) < 1e-9)
    },
    TestCase(name: "statusLine JSON fills optional extras only when present") {
        let withExtras = ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: "{\"five_hour\":{\"used_percentage\":10}}"),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        )
        try require(withExtras?.extras["model"] == "Opus")
        try require(withExtras?.extras["context"] == "8%")
        try require(withExtras?.extras["cost"] == "$0.01")

        let withoutExtras = ClaudeStatusLineParser.parse(
            claudeFixture(rateLimits: "{\"five_hour\":{\"used_percentage\":10}}", extras: false),
            observedAt: referenceNow,
            profileName: ".claude",
            sourcePath: "x"
        )
        try require(withoutExtras?.extras.isEmpty == true, "absent fields must not appear")
    },
    TestCase(name: "Codex JSONL reads the newest rate limit windows") {
        let text = "{\"broken\":\"leading line cut in half\"" + "\n" + codexWindowsLine + "\n"
        let snapshot = CodexSessionParser.parseLatest(
            text: text,
            observedAtFallback: referenceNow,
            profileName: ".codex-work",
            sourcePath: "/tmp/rollout.jsonl"
        )
        try require(snapshot != nil)
        guard let snapshot else { return }
        try require(snapshot.provider == .codex)
        try require(snapshot.windows.map(\.label) == ["5時間", "7日"])
        try require(abs(snapshot.windows[0].usedPercentage - 17) < 1e-9)
        try require(abs(snapshot.windows[1].usedPercentage - 88) < 1e-9)
        try require(snapshot.windows[1].resetsAt == Date(timeIntervalSince1970: 1_789_805_930))
        try require(snapshot.extras["total_tokens"] == "18703")
        try require(snapshot.note == nil)
        // タイムスタンプは行の ISO8601（小数秒あり）から取る。2026-09-15T13:28:48.436Z。
        try require(
            abs(snapshot.observedAt.timeIntervalSince1970 - 1_789_478_928.436) < 0.01,
            "observedAt was \(snapshot.observedAt)"
        )
    },
    TestCase(name: "Codex JSONL falls back past a credit-depleted line and keeps the reason") {
        let filler = """
            {"timestamp":"2026-09-15T14:00:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
            """
        let text = [
            "{\"partial\":true, cut",
            codexWindowsLine,
            filler,
            codexDepletedLine,
            "{\"timestamp\":\"2026-09-16T03:50:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_c",
        ].joined(separator: "\n")

        let snapshot = CodexSessionParser.parseLatest(
            text: text,
            observedAtFallback: referenceNow,
            profileName: ".codex-work",
            sourcePath: "/tmp/rollout.jsonl"
        )
        try require(snapshot != nil)
        guard let snapshot else { return }
        try require(
            snapshot.windows.map(\.label) == ["5時間", "7日"],
            "older windows must survive the depleted line"
        )
        try require(abs(snapshot.windows[1].usedPercentage - 88) < 1e-9)
        try require(
            snapshot.note == "クレジット切れ（workspace_member_credits_depleted）",
            "note was \(snapshot.note ?? "nil")"
        )
    },
    TestCase(name: "Codex JSONL keeps only the reason when no window was ever seen") {
        let snapshot = CodexSessionParser.parseLatest(
            text: codexDepletedLine,
            observedAtFallback: referenceNow,
            profileName: ".codex-personal",
            sourcePath: "/tmp/rollout.jsonl"
        )
        try require(snapshot?.windows.isEmpty == true)
        try require(snapshot?.note == "クレジット切れ（workspace_member_credits_depleted）")
        try require(snapshot?.extras["total_tokens"] == nil, "info:null must not produce total_tokens")
        // 上限到達は「いつの話か」まで持ち回る（駆動値の 5 時間ルールで使う）。
        try require(snapshot?.rateLimitReachedType == "workspace_member_credits_depleted")
        try require(
            abs((snapshot?.noteObservedAt ?? .distantPast).timeIntervalSince1970 - 1_789_530_569.337) < 0.01,
            "note time was \(snapshot?.noteObservedAt.map(String.init(describing:)) ?? "nil")"
        )

        try require(CodexSessionParser.parseLatest(
            text: "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\"}}",
            observedAtFallback: referenceNow,
            profileName: ".codex",
            sourcePath: "x"
        ) == nil, "a log without token_count must be nil")
    },
    TestCase(name: "Codex window labels follow window_minutes") {
        try require(CodexSessionParser.windowLabel(minutes: 300) == "5時間")
        try require(CodexSessionParser.windowLabel(minutes: 10_080) == "7日")
        try require(CodexSessionParser.windowLabel(minutes: 1_440) == "1日")
        try require(CodexSessionParser.windowLabel(minutes: 1_439) == "24時間")
        try require(CodexSessionParser.windowLabel(minutes: 90) == "1.5時間")
        try require(CodexSessionParser.windowLabel(minutes: 30) == "30分")
        try require(CodexSessionParser.windowLabel(minutes: 0) == "枠")
    },
    TestCase(name: "Expired windows count as zero and values are clamped") {
        let expired = AIUsageWindow(
            label: "5時間",
            usedPercentage: 90,
            resetsAt: referenceNow.addingTimeInterval(-1)
        )
        try require(AIUsageAggregator.effectiveUsedPercentage(expired, now: referenceNow) == 0)

        let live = AIUsageWindow(
            label: "7日",
            usedPercentage: 130,
            resetsAt: referenceNow.addingTimeInterval(60)
        )
        try require(AIUsageAggregator.effectiveUsedPercentage(live, now: referenceNow) == 100)

        let noReset = AIUsageWindow(label: "7日", usedPercentage: -5, resetsAt: nil)
        try require(AIUsageAggregator.effectiveUsedPercentage(noReset, now: referenceNow) == 0)
    },
    TestCase(name: "Drive value is the maximum across enabled providers") {
        let future = referenceNow.addingTimeInterval(3_600)
        let claude = AIUsageSnapshot(
            provider: .claudeCode,
            profileName: ".claude-work",
            windows: [
                AIUsageWindow(label: "5時間", usedPercentage: 23, resetsAt: future),
                AIUsageWindow(label: "7日", usedPercentage: 41, resetsAt: future),
            ],
            observedAt: referenceNow,
            sourcePath: "a"
        )
        let codex = AIUsageSnapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [
                AIUsageWindow(label: "5時間", usedPercentage: 17, resetsAt: future),
                AIUsageWindow(label: "7日", usedPercentage: 88, resetsAt: future),
            ],
            observedAt: referenceNow,
            sourcePath: "b"
        )
        let both = Set(AIUsageProvider.allCases)
        try require(
            AIUsageAggregator.driveValue(snapshots: [claude, codex], enabled: both, now: referenceNow) == 88
        )
        let binding = AIUsageAggregator.bindingWindow(
            snapshots: [claude, codex],
            enabled: both,
            now: referenceNow
        )
        try require(binding?.snapshot.provider == .codex)
        try require(binding?.window.label == "7日")

        try require(AIUsageAggregator.driveValue(
            snapshots: [claude, codex],
            enabled: [.claudeCode],
            now: referenceNow
        ) == 41, "disabled providers must be excluded")

        try require(AIUsageAggregator.driveValue(
            snapshots: [],
            enabled: both,
            now: referenceNow
        ) == nil, "no snapshots means no drive value")

        let empty = AIUsageSnapshot(
            provider: .codex,
            profileName: ".codex",
            windows: [],
            observedAt: referenceNow,
            sourcePath: "c"
        )
        try require(AIUsageAggregator.driveValue(
            snapshots: [empty],
            enabled: both,
            now: referenceNow
        ) == nil, "a snapshot without windows means no drive value")
        try require(AIUsageAggregator.bindingWindow(
            snapshots: [empty],
            enabled: both,
            now: referenceNow
        ) == nil)
    },
    TestCase(name: "Reset time formatting switches on the calendar day") {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 1_789_400_000)
        try require(AIUsageAggregator.formatResetsAt(nil, now: now, calendar: calendar) == "")
        try require(AIUsageAggregator.formatResetsAt(
            now.addingTimeInterval(-1),
            now: now,
            calendar: calendar
        ) == "リセット済み")
        try require(AIUsageAggregator.formatResetsAt(
            now,
            now: now,
            calendar: calendar
        ) == "リセット済み", "the boundary counts as already reset")

        // now は 2026-09-14 15:33:20 UTC。
        let sameDay = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 14, hour: 18, minute: 5
        ))
        try require(
            AIUsageAggregator.formatResetsAt(sameDay, now: now, calendar: calendar) == "18:05 リセット",
            "got \(AIUsageAggregator.formatResetsAt(sameDay, now: now, calendar: calendar))"
        )

        let later = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 19, hour: 8, minute: 18
        ))
        try require(
            AIUsageAggregator.formatResetsAt(later, now: now, calendar: calendar) == "9/19 08:18 リセット",
            "got \(AIUsageAggregator.formatResetsAt(later, now: now, calendar: calendar))"
        )
    },
    TestCase(name: "Status line text lists every window and degrades to empty") {
        let snapshot = AIUsageSnapshot(
            provider: .claudeCode,
            profileName: ".claude",
            windows: [
                AIUsageWindow(label: "5時間", usedPercentage: 23.4, resetsAt: nil),
                AIUsageWindow(label: "7日", usedPercentage: 40.6, resetsAt: nil),
            ],
            observedAt: referenceNow,
            sourcePath: "a"
        )
        try require(AIUsageAggregator.formatStatusLine(snapshot) == "Claude 5時間 23% · 7日 41%")
        try require(AIUsageAggregator.formatStatusLine(nil) == "")
        let noteOnly = AIUsageSnapshot(
            provider: .codex,
            profileName: ".codex",
            windows: [],
            observedAt: referenceNow,
            note: "クレジット切れ",
            sourcePath: "b"
        )
        try require(AIUsageAggregator.formatStatusLine(noteOnly) == "クレジット切れ")
    },
    TestCase(name: "Installer adds a statusLine when none exists and keeps other keys") {
        let ourCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/Apps/My App/MenuBarPet")
        try require(ourCommand == "\"/Apps/My App/MenuBarPet\" --statusline")

        let original = Data("{\"model\":\"opus\",\"permissions\":{\"allow\":[\"Bash\"]}}".utf8)
        let updated = ClaudeStatusLineInstaller.install(settingsData: original, command: ourCommand)
        let root = try JSONSerialization.jsonObject(with: updated) as? [String: Any]
        let statusLine = root?["statusLine"] as? [String: Any]
        try require(statusLine?["type"] as? String == "command")
        try require(statusLine?["command"] as? String == ourCommand)
        try require(root?["model"] as? String == "opus", "other keys must survive")
        try require(root?["permissions"] != nil, "nested keys must survive")
        try require(ClaudeStatusLineInstaller.isInstalled(settingsData: updated))
        try require(!ClaudeStatusLineInstaller.isInstalled(settingsData: original))
        try require(!ClaudeStatusLineInstaller.isInstalled(settingsData: nil))

        let fromNothing = ClaudeStatusLineInstaller.install(settingsData: nil, command: ourCommand)
        try require(ClaudeStatusLineInstaller.isInstalled(settingsData: fromNothing))
    },
    TestCase(name: "Installer chains an existing statusLine through --then and is idempotent") {
        let binary = "/Apps/MenuBarPet"
        let ourCommand = ClaudeStatusLineInstaller.command(forBinaryPath: binary)
        let existing = "jq -r '\"[\\(.model.display_name)]\"'"
        let original = Data(
            (try? JSONSerialization.data(withJSONObject: [
                "statusLine": ["type": "command", "command": existing, "padding": 2],
            ])) ?? Data()
        )

        let installed = ClaudeStatusLineInstaller.install(settingsData: original, command: ourCommand)
        let root = try JSONSerialization.jsonObject(with: installed) as? [String: Any]
        let statusLine = root?["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String ?? ""
        try require(command.hasPrefix(ourCommand), "our command must come first")
        try require(command.contains("--then"), "command was \(command)")
        try require(statusLine?["padding"] as? Int == 2, "unrelated statusLine keys must survive")
        try require(
            ClaudeStatusLineInstaller.wrappedCommand(in: command) == existing,
            "round trip failed: \(ClaudeStatusLineInstaller.wrappedCommand(in: command) ?? "nil")"
        )

        let again = ClaudeStatusLineInstaller.install(settingsData: installed, command: ourCommand)
        try require(again == installed, "installing twice must change nothing")

        let restored = ClaudeStatusLineInstaller.uninstall(settingsData: installed)
        let restoredRoot = try JSONSerialization.jsonObject(with: restored) as? [String: Any]
        let restoredStatusLine = restoredRoot?["statusLine"] as? [String: Any]
        try require(restoredStatusLine?["command"] as? String == existing, "original command must return")
        try require(restoredStatusLine?["padding"] as? Int == 2)
    },
    TestCase(name: "Uninstall removes our statusLine and leaves other people's alone") {
        let ourCommand = ClaudeStatusLineInstaller.command(forBinaryPath: "/Apps/MenuBarPet")
        let installed = ClaudeStatusLineInstaller.install(
            settingsData: Data("{\"model\":\"opus\"}".utf8),
            command: ourCommand
        )
        let removed = ClaudeStatusLineInstaller.uninstall(settingsData: installed)
        let root = try JSONSerialization.jsonObject(with: removed) as? [String: Any]
        try require(root?["statusLine"] == nil, "statusLine must be gone")
        try require(root?["model"] as? String == "opus", "other keys must survive")

        let foreign = Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"echo hi\"}}".utf8)
        try require(
            ClaudeStatusLineInstaller.uninstall(settingsData: foreign) == foreign,
            "someone else's statusLine must be untouched"
        )
    },
    TestCase(name: "Old settings JSON decodes with the new keys at their defaults") {
        let legacy = Data("{\"isPaused\":true,\"character\":\"hamsterWheel\"}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try require(settings.isPaused)
        try require(settings.character == .hamsterWheel)
        try require(settings.metricSource == .cpu, "metricSource must default to CPU")
        try require(settings.aiUsageProviders == Set(AIUsageProvider.allCases))

        let roundTripped = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(AppSettings(
                metricSource: .aiUsage,
                aiUsageProviders: [.codex]
            ))
        )
        try require(roundTripped.metricSource == .aiUsage)
        try require(roundTripped.aiUsageProviders == [.codex])

        let unknown = Data("{\"metricSource\":\"quantum\",\"aiUsageProviders\":[\"gemini\"]}".utf8)
        let fallback = try JSONDecoder().decode(AppSettings.self, from: unknown)
        try require(fallback.metricSource == .cpu, "unknown metric sources fall back")
        try require(fallback.aiUsageProviders == Set(AIUsageProvider.allCases))
    },
    TestCase(name: "Config discovery picks real homes and skips ~/.claude.json") {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default

        for (name, child) in [(".claude", "settings.json"), (".claude-work", "settings.json")] {
            let directory = home.appendingPathComponent(name)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: directory.appendingPathComponent(child))
        }
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".claude-empty"),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json"))
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".codex-work/sessions"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".codexfoo/sessions"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".codex-nosessions"),
            withIntermediateDirectories: true
        )

        let claude = AIUsagePaths.discoverConfigDirectories(.claude, in: home, using: fileManager)
        try require(
            claude.map(\.profileName) == [".claude", ".claude-work"],
            "found \(claude.map(\.profileName))"
        )
        let codex = AIUsagePaths.discoverConfigDirectories(.codex, in: home, using: fileManager)
        try require(codex.map(\.profileName) == [".codex-work"], "found \(codex.map(\.profileName))")
    },
    TestCase(name: "Usage paths follow the env override and the profile naming rules") {
        let home = URL(fileURLWithPath: "/Users/someone")
        let standard = AIUsagePaths.usageDirectory(homeDirectory: home, environment: [:])
        try require(
            standard.path == "/Users/someone/Library/Application Support/MenuBarPet/AIUsage",
            standard.path
        )
        let overridden = AIUsagePaths.usageDirectory(
            homeDirectory: home,
            environment: [AIUsagePaths.usageDirectoryEnvironmentKey: "/tmp/usage"]
        )
        try require(overridden.path == "/tmp/usage")

        try require(AIUsagePaths.claudeUsageFileURL(
            directory: overridden,
            profileName: ".claude-work"
        ).lastPathComponent == "claude-.claude-work.json")
        try require(
            AIUsagePaths.claudeProfileName(fromFileName: "claude-.claude-work.json") == ".claude-work"
        )
        try require(AIUsagePaths.claudeProfileName(fromFileName: "notes.json") == nil)

        try require(AIUsagePaths.claudeProfileName(
            environment: [:],
            homeDirectory: home
        ) == ".claude")
        try require(AIUsagePaths.claudeProfileName(
            environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.claude-work/"],
            homeDirectory: home
        ) == ".claude-work")
        try require(AIUsagePaths.claudeProfileName(
            environment: ["CLAUDE_CONFIG_DIR": "  "],
            homeDirectory: home
        ) == ".claude")
    },
    TestCase(name: "The usage store round trips a statusLine payload") {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIUsageStore(directoryURL: directory.appendingPathComponent("AIUsage"))
        try store.write(
            claudeFixture(rateLimits: "{\"five_hour\":{\"used_percentage\":23,\"resets_at\":1738425600}}"),
            profileName: ".claude-work"
        )
        try store.write(Data("not json".utf8), profileName: ".claude-broken")

        let snapshots = store.readClaudeSnapshots()
        try require(snapshots.count == 1, "broken files must be skipped, got \(snapshots.count)")
        try require(snapshots[0].profileName == ".claude-work")
        try require(snapshots[0].windows.map(\.label) == ["5時間"])
        try require(snapshots[0].sourcePath.hasSuffix("claude-.claude-work.json"))
    },
    TestCase(name: "Codex scanner reads the newest session file per profile") {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default

        let older = home.appendingPathComponent(".codex-work/sessions/2026/09/14")
        let newer = home.appendingPathComponent(".codex-work/sessions/2026/09/15")
        try fileManager.createDirectory(at: older, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: newer, withIntermediateDirectories: true)
        let stale = """
            {"timestamp":"2026-09-14T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count",\
            "info":null,"rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,\
            "resets_at":1789492314},"secondary":null,"rate_limit_reached_type":null}}}
            """
        try Data((codexWindowsLine + "\n").utf8)
            .write(to: newer.appendingPathComponent("rollout-2026-09-15T13-00-00-aaa.jsonl"))
        try Data((stale + "\n").utf8)
            .write(to: older.appendingPathComponent("rollout-2026-09-14T09-00-00-bbb.jsonl"))
        try Data("ignore me".utf8).write(to: newer.appendingPathComponent("notes.txt"))

        var scanner = CodexSessionScanner()
        let first = scanner.snapshots(homeDirectory: home, fileManager: fileManager)
        try require(first.count == 1, "one snapshot per profile, got \(first.count)")
        try require(first[0].profileName == ".codex-work")
        try require(
            first[0].windows.map(\.label) == ["5時間", "7日"],
            "the newest session must win, got \(first[0].windows.map(\.label))"
        )
        try require(abs(first[0].windows[0].usedPercentage - 17) < 1e-9, "stale file must lose")
        // 同じ指紋なら再パースせず同じ結果を返す。
        let second = scanner.snapshots(homeDirectory: home, fileManager: fileManager)
        try require(second == first, "cached read must match")
    },
]
