import Foundation

enum DomainSelfTest {
    static func run() -> Bool {
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

        if failures.isEmpty {
            print("PASS: 4 domain test groups")
            return true
        }
        failures.forEach { print("FAIL: \($0)") }
        return false
    }
}
