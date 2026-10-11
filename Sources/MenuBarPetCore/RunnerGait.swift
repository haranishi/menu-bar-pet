import Foundation

/// Contact travels backwards at a steady speed; recovery lifts the paw and returns it.
public enum RunnerGait {
    public static let contactFraction = 0.4

    public static func step(phase: Double, stride: Double) -> (x: Double, lift: Double) {
        let p = PetMotion.normalizedPhase(phase)
        let amplitude = stride.isFinite ? max(0, stride) : 0
        if p < contactFraction {
            return (amplitude * (1 - 2 * p / contactFraction), 0)
        }
        let t = (p - contactFraction) / (1 - contactFraction)
        let t2 = t * t
        let t3 = t2 * t
        let velocity = -2 * amplitude * (1 - contactFraction) / contactFraction
        let x = (-amplitude) * (2 * t3 - 3 * t2 + 1)
            + velocity * (t3 - 2 * t2 + t)
            + amplitude * (-2 * t3 + 3 * t2)
            + velocity * (t3 - t2)
        return (x, 2.4 * pow(sin(.pi * t), 2))
    }
}
