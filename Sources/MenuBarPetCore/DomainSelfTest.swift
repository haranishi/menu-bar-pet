import Foundation

public enum DomainSelfTest {
    public static func run() -> Bool {
        var failures: [String] = []

        let mappings: [(Double, PetState)] = [
            (5, .resting), (35, .normal), (60, .running), (80, .sweating), (95, .onFire),
        ]
        for (usage, expected) in mappings where
            PetStateMachine.classify(usage, thresholds: Sensitivity.standard.thresholds) != expected {
            failures.append("classification \(usage) -> \(expected)")
        }

        var upward = PetStateMachine(alpha: 1)
        let upwardStates = (0..<3).map { _ in upward.ingest(80, sensitivity: .standard).state }
        if upwardStates != [.normal, .normal, .sweating] {
            failures.append("upward transition requires three samples")
        }

        var downward = upward
        let downwardStates = (0..<5).map { _ in downward.ingest(40, sensitivity: .standard).state }
        if downwardStates != [.sweating, .sweating, .sweating, .sweating, .normal] {
            failures.append("downward transition requires five samples")
        }

        var clamped = PetStateMachine(alpha: 1)
        if clamped.ingest(-10, sensitivity: .standard).usage != 0 ||
            clamped.ingest(130, sensitivity: .standard).usage != 100 {
            failures.append("usage clamping")
        }

        let now = Date(timeIntervalSince1970: 1_789_400_000)
        let snapshot = AIUsageSnapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [
                AIUsageWindow(label: "5時間", usedPercentage: 17, resetsAt: now.addingTimeInterval(-1)),
                AIUsageWindow(label: "7日", usedPercentage: 88, resetsAt: now.addingTimeInterval(600)),
            ],
            observedAt: now,
            sourcePath: "self-test"
        )
        if AIUsageAggregator.driveValue(
            snapshots: [snapshot],
            enabled: Set(AIUsageProvider.allCases),
            now: now
        ) != 88 {
            failures.append("AI usage drive value takes the maximum live window")
        }
        if AIUsageAggregator.driveValue(
            snapshots: [snapshot],
            enabled: [.claudeCode],
            now: now
        ) != nil {
            failures.append("AI usage drive value skips disabled providers")
        }

        if failures.isEmpty {
            print("PASS: 5 domain test groups")
            return true
        }
        failures.forEach { print("FAIL: \($0)") }
        return false
    }
}
