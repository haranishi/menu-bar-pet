import Foundation
import MenuBarPetCore

let rustIntegrationTests: [TestCase] = [
    TestCase(name: "Cached readout follows reset boundaries without a new snapshot") {
        var cache = MenuBarPresentationCache()
        let reset = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshots = [AIUsageSnapshot(
            provider: .codex, profileName: "synthetic", windows: [AIUsageWindow(
                label: "5時間", usedPercentage: 93, resetsAt: reset, durationMinutes: 300
            )], observedAt: reset.addingTimeInterval(-60), sourcePath: "synthetic"
        )]
        let before = cache.presentation(snapshots: snapshots, enabled: [.codex], now: reset.addingTimeInterval(-1))
        let after = cache.presentation(snapshots: snapshots, enabled: [.codex], now: reset)
        try require(before.rows == ["Codex   93  --"])
        try require(after.rows == ["Codex    0  --"])
        try require(after.tooltip.contains("リセット済み"))
    },
    TestCase(name: "Cached readout immediately follows provider and snapshot changes") {
        var cache = MenuBarPresentationCache()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func snapshot(_ used: Double) -> AIUsageSnapshot {
            AIUsageSnapshot(provider: .codex, profileName: "synthetic", windows: [
                AIUsageWindow(label: "5時間", usedPercentage: used, resetsAt: nil, durationMinutes: 300)
            ], observedAt: now, sourcePath: "synthetic")
        }
        let first = cache.presentation(snapshots: [snapshot(10)], enabled: [.codex], now: now)
        let changed = cache.presentation(snapshots: [snapshot(30)], enabled: [.codex], now: now)
        try require(first.rows != changed.rows)
        let disabled = cache.presentation(snapshots: [snapshot(30)], enabled: [.claudeCode], now: now)
        try require(disabled.rows == ["Claude  --  --"])
    },
    TestCase(name: "Rust machine copies have independent state and reset keeps smoothing") {
        var first = PetStateMachine(alpha: 1)
        var copy = first
        for _ in 0..<3 { _ = first.ingest(100, sensitivity: .standard) }
        try require(first.state == .onFire && copy.state == .normal)
        try require(copy.ingest(0, sensitivity: .standard).smoothedUsage == 0)
        first.reset()
        try require(first.state == .normal)
        try require(first.ingest(0, sensitivity: .standard).smoothedUsage == 0)
    },
    TestCase(name: "Invalid window timestamps fall back to the newest event timestamp") {
        let text = """
        {"type":"event_msg","timestamp":"invalid","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":40}},"rate_limits":{"primary":{"used_percent":20,"window_minutes":300}}}}
        {"type":"event_msg","timestamp":"2026-01-01T01:00:00Z","payload":{"type":"token_count","rate_limits":{"rate_limit_reached_type":"usage_limit_reached"}}}
        """
        let value = CodexSessionParser.parseLatest(
            text: text, observedAtFallback: .distantPast, profileName: "synthetic", sourcePath: "synthetic"
        )
        try require(value?.observedAt == Date(timeIntervalSince1970: 1_767_229_200))
        try require(value?.windows.first?.usedPercentage == 20)
    },
    TestCase(name: "Rust log tails recover a clipped UTF-8 character within the byte limit") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollout-synthetic.jsonl")
        let event = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}}"
        try Data("猫猫\n\(event)\n".utf8).write(to: url)
        let limit = event.utf8.count + 4
        let tail = CodexSessionScanner.readTail(of: url, maxBytes: limit)
        try require(tail == event + "\n")
        try require((tail?.utf8.count ?? 0) <= limit)
        try require(CodexSessionScanner.readTail(of: url, maxBytes: 0) == nil)
    },
]
