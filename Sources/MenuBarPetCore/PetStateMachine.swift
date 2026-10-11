import CMbpCore
import Foundation

public struct PetStateSnapshot: Equatable, Sendable {
    public let usage: Double
    public let smoothedUsage: Double
    public let state: PetState
}

/// Owns the Rust state machine's inline C representation.
public struct PetStateMachine: Sendable {
    private var core: MbpMachine
    public var state: PetState { PetState(rawValue: Int(core.state)) ?? .normal }
    public init(alpha: Double = 0.35) { core = mbp_machine_new(alpha) }
    public mutating func ingest(_ rawUsage: Double, sensitivity: Sensitivity) -> PetStateSnapshot {
        let code: UInt32 = switch sensitivity { case .relaxed: 0; case .standard: 1; case .sensitive: 2 }
        let value = mbp_machine_ingest(&core, rawUsage, code)
        return PetStateSnapshot(
            usage: value.usage, smoothedUsage: value.smoothed,
            state: PetState(rawValue: Int(value.state)) ?? .normal
        )
    }
    public mutating func reset() { core = mbp_machine_new(core.alpha) }
    public static func classify(_ usage: Double, thresholds: [Double]) -> PetState {
        precondition(thresholds.count == 4)
        return PetState(rawValue: Int(mbp_classify(
            usage, thresholds[0], thresholds[1], thresholds[2], thresholds[3]
        ))) ?? .normal
    }
}
