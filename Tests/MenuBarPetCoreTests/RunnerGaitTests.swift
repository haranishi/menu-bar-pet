import Foundation
import MenuBarPetCore

let runnerGaitTests: [TestCase] = [
    TestCase(name: "Paw contact is planted and recovery lifts with continuous position and velocity") {
        let h = 0.00001
        for boundary in [0.0, RunnerGait.contactFraction, 1.0] {
            let before = RunnerGait.step(phase: boundary - h, stride: 2.8)
            let at = RunnerGait.step(phase: boundary, stride: 2.8)
            let after = RunnerGait.step(phase: boundary + h, stride: 2.8)
            try require(abs(before.x - after.x) < 0.001)
            try require(abs((at.x - before.x) / h - (after.x - at.x) / h) < 0.02)
            try require(abs((at.lift - before.lift) / h - (after.lift - at.lift) / h) < 0.02)
        }
        for index in 0...1000 {
            let p = Double(index) / 1000
            let step = RunnerGait.step(phase: p, stride: 2.8)
            try require(step.x.isFinite && (0...2.4).contains(step.lift))
            if p < RunnerGait.contactFraction { try require(step.lift == 0) }
        }
        try require(RunnerGait.step(phase: 0.7, stride: 2.8).lift > 2)
    },
    TestCase(name: "Shiba bounce has zero velocity at takeoff, apex and loop seam") {
        let h = 0.00001
        for boundary in [0.0, ShibaMotion.ascentFraction, 1.0] {
            let before = ShibaMotion.asymmetricBounce(phase: boundary - h)
            let at = ShibaMotion.asymmetricBounce(phase: boundary)
            let after = ShibaMotion.asymmetricBounce(phase: boundary + h)
            try require(abs((at - before) / h) < 0.001)
            try require(abs((after - at) / h) < 0.001)
        }
    }
]
