import AppKit
import MenuBarPetCore

/// Uses synthetic data and never starts timers, changes settings or reads AI sessions.
@MainActor
enum PerformanceBenchmark {
    static func run(iterations: Int) {
        let now = Date()
        let resets = now.addingTimeInterval(86_400)
        let usage = BenchmarkUsage(snapshots: AIUsageProvider.allCases.map { provider in
            AIUsageSnapshot(
                provider: provider, profileName: "synthetic", windows: [
                    AIUsageWindow(label: "5時間", usedPercentage: 23, resetsAt: resets, durationMinutes: 300),
                    AIUsageWindow(label: "7日", usedPercentage: 89, resetsAt: resets, durationMinutes: 10_080)
                ], observedAt: now, sourcePath: "synthetic"
            )
        })
        let model = PetViewModel(
            cpuSampler: BenchmarkCPU(), settingsStore: BenchmarkSettings(),
            customRunnerStore: CustomRunnerStore(directoryURL:
                FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ), aiUsage: usage
        )
        let claude = Data("""
            {"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":2000000000},"seven_day":{"used_percentage":89,"resets_at":2000000000}}}
            """.utf8)
        let event = """
            {"type":"event_msg","timestamp":"2026-10-11T00:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":40}},"rate_limits":{"primary":{"used_percent":23,"window_minutes":300,"resets_at":2000000000}}}}
            """
        let noise = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"progress\",\"text\":\""
            + String(repeating: "x", count: 490) + "\"}}\n"
        let log = event + "\n" + String(repeating: noise, count: 800)
        let parserIterations = max(1, iterations / 10)
        var sink = 0
        func measure(_ count: Int, _ operation: (Int) -> Void) -> Double {
            let started = ProcessInfo.processInfo.systemUptime
            for index in 0..<count { autoreleasepool { operation(index) } }
            return (ProcessInfo.processInfo.systemUptime - started) * 1_000
        }
        // Warm up fonts and drawing before either measurement.
        _ = MenuBarComposer.compose(pet: NSImage(size: PetRenderer.pointSize), rows: model.menuBarRows, isDark: false)
        let presentation = measure(iterations) { _ in
            sink += model.menuBarRows.count
            sink += model.menuBarTooltip?.count ?? 0
            sink += model.accessibilitySummary.count
        }
        let frames = measure(iterations) { index in
            let pet = PetRenderer.render(
                character: .shibaInu, state: .running, phase: Double(index % 12) / 12,
                isDarkAppearance: false, reduceMotion: false
            )
            let image = MenuBarComposer.compose(pet: pet, rows: model.menuBarRows, isDark: false)
            sink += Int(image.size.width)
            sink += model.menuBarTooltip?.count ?? 0
            sink += model.accessibilitySummary.count
        }
        let claudeParse = measure(parserIterations) { _ in
            sink += ClaudeStatusLineParser.parse(
                claude, observedAt: now, profileName: "synthetic", sourcePath: "synthetic"
            )?.windows.count ?? 0
        }
        let codexParse = measure(parserIterations) { _ in
            sink += CodexSessionParser.parseLatest(
                text: log, observedAtFallback: now, profileName: "synthetic", sourcePath: "synthetic"
            )?.windows.count ?? 0
        }
        let report: [String: Any] = [
            "iterations": iterations, "parser_iterations": parserIterations,
            "codex_tail_bytes": log.utf8.count, "presentation_ms": presentation,
            "frames_ms": frames, "claude_parse_ms": claudeParse,
            "codex_parse_ms": codexParse, "sink": sink
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}

@MainActor
private final class BenchmarkCPU: CPUSampling {
    func readUsage() -> Double? { 50 }
    func reset() {}
}

@MainActor
private final class BenchmarkSettings: SettingsStoring {
    func load() -> AppSettings { AppSettings(metricSource: .aiUsage) }
    func save(_ settings: AppSettings) {}
}

@MainActor
private final class BenchmarkUsage: AIUsageProviding {
    let snapshots: [AIUsageSnapshot]
    init(snapshots: [AIUsageSnapshot]) { self.snapshots = snapshots }
    func refresh() {}
    func setActive(_ active: Bool) {}
}
