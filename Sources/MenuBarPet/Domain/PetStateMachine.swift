import Foundation

struct PetStateSnapshot: Equatable, Sendable {
    let usage: Double
    let smoothedUsage: Double
    let state: PetState
}

struct PetStateMachine: Sendable {
    private(set) var state: PetState = .normal
    private var smoothedUsage: Double?
    private var candidate: PetState?
    private var candidateCount = 0
    private let alpha: Double

    init(alpha: Double = 0.35) {
        self.alpha = min(max(alpha, 0.01), 1)
    }

    mutating func ingest(_ rawUsage: Double, sensitivity: Sensitivity) -> PetStateSnapshot {
        let usage = min(max(rawUsage, 0), 100)
        let smoothed = smoothedUsage.map { alpha * usage + (1 - alpha) * $0 } ?? usage
        smoothedUsage = smoothed

        let upwardTarget = Self.classify(smoothed, thresholds: sensitivity.thresholds)
        let downwardThresholds = sensitivity.thresholds.map { max(0, $0 - 5) }
        let downwardTarget = Self.classify(smoothed, thresholds: downwardThresholds)
        let target = upwardTarget.rawValue > state.rawValue ? upwardTarget : downwardTarget

        if target == state {
            candidate = nil
            candidateCount = 0
        } else {
            if candidate == target {
                candidateCount += 1
            } else {
                candidate = target
                candidateCount = 1
            }

            let requiredSamples = target.rawValue > state.rawValue ? 3 : 5
            if candidateCount >= requiredSamples {
                state = target
                candidate = nil
                candidateCount = 0
            }
        }

        return PetStateSnapshot(usage: usage, smoothedUsage: smoothed, state: state)
    }

    mutating func reset() {
        state = .normal
        smoothedUsage = nil
        candidate = nil
        candidateCount = 0
    }

    static func classify(_ usage: Double, thresholds: [Double]) -> PetState {
        precondition(thresholds.count == 4)
        switch usage {
        case ..<thresholds[0]: return .resting
        case ..<thresholds[1]: return .normal
        case ..<thresholds[2]: return .running
        case ..<thresholds[3]: return .sweating
        default: return .onFire
        }
    }
}
