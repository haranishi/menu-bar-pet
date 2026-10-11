import Foundation
import MenuBarPetCore

let petMotionTests: [TestCase] = [
    TestCase(name: "Phase always remains in [0, 1)") {
        for initialPhase in [-1_000.25, -1, -0.1, 0, 0.5, 1, 20.75, .infinity, .nan] {
            var clock = PetMotionClock(phase: initialPhase)
            for step in 0..<2_000 {
                clock.advance(elapsed: Double(step % 9) / 120, cpu: Double(step % 121) - 10)
                try require(clock.phase >= 0 && clock.phase < 1, "phase was \(clock.phase)")
            }
        }
    },
    TestCase(name: "Cycle duration is clipped and strictly decreases with CPU") {
        try require(abs(PetMotion.cycleDuration(cpu: -1) - 2.2) < 1e-12)
        try require(abs(PetMotion.cycleDuration(cpu: 0) - 2.2) < 1e-12)
        try require(abs(PetMotion.cycleDuration(cpu: 100) - 0.45) < 1e-12)
        try require(abs(PetMotion.cycleDuration(cpu: 101) - 0.45) < 1e-12)
        var previous = PetMotion.cycleDuration(cpu: 0)
        for cpu in 1...100 {
            let current = PetMotion.cycleDuration(cpu: Double(cpu))
            try require(current < previous, "duration did not decrease at CPU \(cpu)")
            previous = current
        }
    },
    TestCase(name: "Frame rate guarantees twelve frames per cycle within caps") {
        for state in PetState.allCases {
            let stateMinimum: Double = switch state {
            case .resting: 8
            case .normal, .running: 12
            case .sweating, .onFire: 15
            }
            for cpuStep in -100...1_100 {
                let cpu = Double(cpuStep) / 10
                let fps = PetMotion.framesPerSecond(state: state, cpu: cpu)
                try require(fps >= stateMinimum - 1e-12, "\(state) minimum at CPU \(cpu)")
                try require(fps <= 30 + 1e-12, "\(state) cap at CPU \(cpu)")
                try require(
                    fps * PetMotion.cycleDuration(cpu: cpu) >= 12 - 1e-12,
                    "\(state) frames per cycle at CPU \(cpu)"
                )
            }
        }
    },
    TestCase(name: "Custom frame index is bounded, monotonic, and wraps at one") {
        for count in 1...24 {
            var previous = 0
            for step in 0..<10_000 {
                let index = PetMotion.frameIndex(
                    phase: Double(step) / 10_000,
                    frameCount: count
                )
                try require(index >= 0 && index < count, "count \(count), index \(index)")
                try require(index >= previous, "count \(count), step \(step)")
                previous = index
            }
            try require(PetMotion.frameIndex(phase: 1, frameCount: count) == 0)
        }
    },
    TestCase(name: "Frame rate accounts for every custom frame within caps") {
        for count in 2...24 {
            for state in PetState.allCases {
                let minimum: Double = switch state {
                case .resting: 8
                case .normal, .running: 12
                case .sweating, .onFire: 15
                }
                for cpuStep in -100...1_100 {
                    let cpu = Double(cpuStep) / 10
                    let duration = PetMotion.cycleDuration(cpu: cpu)
                    let fps = PetMotion.framesPerSecond(
                        state: state,
                        cpu: cpu,
                        frameCount: count
                    )
                    try require(fps >= minimum - 1e-12, "\(state) minimum at \(count) frames")
                    try require(fps <= 30 + 1e-12, "\(state) cap at \(count) frames")
                    let wanted = Double(max(12, count))
                    try require(
                        fps * duration >= wanted - 1e-9
                            || abs(fps - 30) < 1e-9
                            || abs(fps - minimum) < 1e-9,
                        "\(state) showed \(fps * duration) of \(wanted) frames at CPU \(cpu)"
                    )
                }
            }
        }
    },
    TestCase(name: "Frame rates and amplitudes follow each state profile") {
        try require(PetMotion.framesPerSecond(state: .resting, cpu: 0) == 8)
        try require(PetMotion.framesPerSecond(state: .normal, cpu: 0) == 12)
        try require(PetMotion.framesPerSecond(state: .running, cpu: 0) == 12)
        try require(PetMotion.framesPerSecond(state: .sweating, cpu: 0) == 15)
        try require(PetMotion.framesPerSecond(state: .onFire, cpu: 0) == 15)
        try require(PetMotion.amplitude(for: .resting) == 0.5)
        try require(PetMotion.amplitude(for: .normal) == 1.5)
        try require(PetMotion.amplitude(for: .running) == 2.5)
        try require(PetMotion.amplitude(for: .sweating) == 3)
        try require(PetMotion.amplitude(for: .onFire) == 3.5)

    },
    TestCase(name: "Hamster wheel angle is continuous and periodic") {
        for step in 0...10_000 {
            let phase = Double(step) / 10_000
            let angle = HamsterMotion.wheelAngle(state: .running, phase: phase)
            let repeated = HamsterMotion.wheelAngle(state: .running, phase: phase + 1)
            try require(abs(sin(angle) - sin(repeated)) < 1e-12)
            try require(abs(cos(angle) - cos(repeated)) < 1e-12)
        }
        let start = HamsterMotion.wheelAngle(state: .running, phase: 0)
        let end = HamsterMotion.wheelAngle(state: .running, phase: 1)
        try require(abs(start - end) < 1e-12)
    },
    TestCase(name: "Hamster wheel step always stays below half a spoke interval") {
        let limit = Double.pi / 5
        try require(HamsterMotion.maximumWheelStepTurns == 0.07)
        for cpu in 0...100 {
            for state in PetState.allCases {
                let fps = PetMotion.framesPerSecond(state: state, cpu: Double(cpu))
                let step = HamsterMotion.wheelPhaseIncrement(
                    elapsed: 1 / fps,
                    cpu: Double(cpu)
                ) * 2 * Double.pi
                try require(step < limit, "CPU \(cpu), fps \(fps), step \(step)")
            }
            for elapsedStep in 0...300 {
                let step = HamsterMotion.wheelPhaseIncrement(
                    elapsed: Double(elapsedStep) / 30,
                    cpu: Double(cpu)
                ) * 2 * Double.pi
                try require(step < limit, "delayed frame at CPU \(cpu), step \(step)")
            }
        }
    },
    TestCase(name: "Hamster effort and overlays scale with state and phase") {
        let normal = HamsterMotion.frame(state: .normal, phase: 0.125, reduceMotion: false)
        let running = HamsterMotion.frame(state: .running, phase: 0.125, reduceMotion: false)
        let fire = HamsterMotion.frame(state: .onFire, phase: 0.125, reduceMotion: false)
        try require(normal.movementIntensity < running.movementIntensity)
        try require(running.movementIntensity < fire.movementIntensity)
        try require(abs(normal.bodyOffsetY) < abs(running.bodyOffsetY))
        try require(abs(running.bodyOffsetY) < abs(fire.bodyOffsetY))

        let large = HamsterMotion.frame(state: .sweating, phase: 0.25, reduceMotion: false)
        let small = HamsterMotion.frame(state: .sweating, phase: 0.75, reduceMotion: false)
        try require(abs(large.overlayPulse - 1.15) < 1e-12)
        try require(abs(small.overlayPulse - 0.85) < 1e-12)

        let reduced = HamsterMotion.frame(state: .onFire, phase: 0.25, reduceMotion: true)
        try require(reduced.bodyOffsetY == 0)
        try require(reduced.overlayPulse == 1)
    },
    TestCase(name: "Resting hamster wheel stays stopped at every phase") {
        for step in 0...1_000 {
            try require(HamsterMotion.wheelAngle(
                state: .resting,
                phase: Double(step) / 1_000
            ) == 0)
        }
    },
    TestCase(name: "Hamster front and rear leg pairs stay in opposite phase") {
        for step in 0...1_000 {
            let legs = HamsterMotion.legPhases(phase: Double(step) / 1_000)
            let front = sin(legs.front * 2 * .pi)
            let rear = sin(legs.rear * 2 * .pi)
            try require(abs(front + rear) < 1e-12)
        }
    },
    TestCase(name: "Hamster content stays inside the canvas in every state and phase") {
        for state in PetState.allCases {
            for step in 0...10_000 {
                let frame = HamsterMotion.frame(
                    state: state,
                    phase: Double(step) / 10_000,
                    reduceMotion: false
                )
                try require(frame.contentBounds.minX >= HamsterMotion.canvas.minX)
                try require(frame.contentBounds.minY >= HamsterMotion.canvas.minY)
                try require(frame.contentBounds.maxX <= HamsterMotion.canvas.maxX)
                try require(frame.contentBounds.maxY <= HamsterMotion.canvas.maxY)
            }
        }
    },
    TestCase(name: "Enlarged hamster body keeps its footing and fits the wheel") {
        try require(HamsterMotion.bodyScale == 1.45)

        // 足裏（拡大前の外接矩形の下端）は拡大後に内輪の底へ着地する
        let footY = HamsterMotion.scaledBodyExtent(state: .running).minY
        let floorY = HamsterMotion.wheelCenter.y - (HamsterMotion.wheelRadius - 1.15)
        try require(abs(footY - floorY) < 0.2, "foot line \(footY) vs floor \(floorY)")

        for state in PetState.allCases {
            let extent = HamsterMotion.scaledBodyExtent(state: state)
            try require(extent.minX >= HamsterMotion.canvas.minX, "\(state) left")
            try require(extent.minY >= HamsterMotion.canvas.minY, "\(state) bottom")
            try require(extent.maxX <= HamsterMotion.canvas.maxX, "\(state) right")
            try require(extent.maxY <= HamsterMotion.canvas.maxY, "\(state) top")

            let before = state == .resting
                ? HamsterMotion.sleepingBodyExtent
                : HamsterMotion.runningBodyExtent
            let scale = HamsterMotion.bodyScale
            try require(abs(extent.width - before.width * scale) < 1e-9, "\(state) width")
            try require(abs(extent.height - before.height * scale) < 1e-9, "\(state) height")
        }

        // 走行時は回し車の外輪（半径 10.1）の縦横いっぱいに収まる
        let cx = HamsterMotion.wheelCenter.x
        let cy = HamsterMotion.wheelCenter.y
        let outer = HamsterMotion.wheelRadius
        let running = HamsterMotion.scaledBodyExtent(state: .running)
        try require(running.minX >= cx - outer, "running body left the wheel")
        try require(running.maxX <= cx + outer, "running body left the wheel")
        try require(running.minY >= cy - outer, "running body left the wheel")
        try require(running.maxY <= cy + outer, "running body left the wheel")

        // 眠っているときは内輪（半径 8.95）から1pt以上はみ出さない
        let inner = outer - 1.15
        let sleeping = HamsterMotion.scaledBodyExtent(state: .resting)
        try require(sleeping.minX >= cx - inner - 1, "sleeping body left the rim")
        try require(sleeping.maxX <= cx + inner + 1, "sleeping body left the rim")
        try require(sleeping.minY >= cy - inner - 1, "sleeping body left the rim")
        try require(sleeping.maxY <= cy + inner + 1, "sleeping body left the rim")
    },
    TestCase(name: "App settings character survives JSON round trip") {
        for character in PetCharacter.allCases {
            let settings = AppSettings(
                isPaused: true,
                character: character
            )
            let data = try JSONEncoder().encode(settings)
            try require(!String(decoding: data, as: UTF8.self).contains("sensitivity"))
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            try require(decoded == settings)
        }
    },
    TestCase(name: "Missing or invalid character falls back to shiba inu") {
        let legacy = Data(#"{"isPaused":true,"sensitivity":"relaxed"}"#.utf8)
        let invalid = Data(#"{"isPaused":false,"sensitivity":"standard","character":"unknown"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        let invalidSettings = try JSONDecoder().decode(AppSettings.self, from: invalid)
        try require(legacySettings.character == .shibaInu)
        try require(invalidSettings.character == .shibaInu)
        try require(AppSettings().character == .shibaInu)
    },
    TestCase(name: "Shiba content stays inside the canvas in every state and phase") {
        for state in PetState.allCases {
            for step in 0...10_000 {
                let frame = ShibaMotion.frame(
                    state: state,
                    phase: Double(step) / 10_000,
                    reduceMotion: false
                )
                try require(frame.contentBounds.minX >= ShibaMotion.canvas.minX, "\(state) left")
                try require(frame.contentBounds.minY >= ShibaMotion.canvas.minY, "\(state) bottom")
                try require(frame.contentBounds.maxX <= ShibaMotion.canvas.maxX, "\(state) right")
                try require(frame.contentBounds.maxY <= ShibaMotion.canvas.maxY, "\(state) top")
                if let overlay = frame.overlayBounds {
                    try require(overlay.minX >= ShibaMotion.canvas.minX)
                    try require(overlay.minY >= ShibaMotion.canvas.minY)
                    try require(overlay.maxX <= ShibaMotion.canvas.maxX)
                    try require(overlay.maxY <= ShibaMotion.canvas.maxY)
                }
            }
        }
    },
    TestCase(name: "Shiba leg pairs oppose and sleeping pose stays still") {
        let reference = ShibaMotion.frame(state: .resting, phase: 0, reduceMotion: false)
        for step in 0...1_000 {
            let phase = Double(step) / 1_000
            let legs = ShibaMotion.legPhases(state: .running, phase: phase)
            try require(abs(
                sin(legs.front * 2 * .pi) + sin(legs.rear * 2 * .pi)
            ) < 1e-12)

            let sleeping = ShibaMotion.frame(state: .resting, phase: phase, reduceMotion: false)
            try require(sleeping.frontLegPhase == reference.frontLegPhase)
            try require(sleeping.rearLegPhase == reference.rearLegPhase)
            try require(sleeping.bounceHeight == reference.bounceHeight)
            try require(sleeping.bodyScaleX == reference.bodyScaleX)
            try require(sleeping.bodyScaleY == reference.bodyScaleY)
            try require(sleeping.forwardLean == reference.forwardLean)
            try require(sleeping.tailSwing == reference.tailSwing)
            try require(sleeping.overlayPulse == reference.overlayPulse)
        }
    },
    TestCase(name: "Shiba bounce is seamless and asymmetric") {
        try require(abs(ShibaMotion.asymmetricBounce(phase: 0)) < 1e-12)
        try require(abs(ShibaMotion.asymmetricBounce(phase: 1)) < 1e-12)
        try require(abs(
            ShibaMotion.asymmetricBounce(phase: 0.2)
                - ShibaMotion.asymmetricBounce(phase: 1.2)
        ) < 1e-12)
        try require(ShibaMotion.ascentFraction != 0.5)
        try require(abs(ShibaMotion.asymmetricBounce(phase: ShibaMotion.ascentFraction) - 1) < 1e-12)
        try require(ShibaMotion.asymmetricBounce(phase: 0.175) > 0.5)
        try require(ShibaMotion.asymmetricBounce(phase: 0.675) > 0.5)
    },
    TestCase(name: "Shiba posture scales with effort and reduced motion freezes it") {
        let normal = ShibaMotion.frame(state: .normal, phase: 0.2, reduceMotion: false)
        let running = ShibaMotion.frame(state: .running, phase: 0.2, reduceMotion: false)
        let fire = ShibaMotion.frame(state: .onFire, phase: 0.2, reduceMotion: false)
        try require(normal.forwardLean < running.forwardLean)
        try require(running.forwardLean < fire.forwardLean)
        try require(normal.bounceHeight < running.bounceHeight)
        try require(running.bounceHeight < fire.bounceHeight)
        try require(ShibaMotion.frame(
            state: .onFire,
            phase: 0.2,
            reduceMotion: true
        ).bounceHeight == 0)
    },
    TestCase(name: "Custom runner store saves loads and deletes frames") {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceB = root.appendingPathComponent("b.png")
        let sourceA = root.appendingPathComponent("a.png")
        try Data([0x42]).write(to: sourceB)
        try Data([0x41]).write(to: sourceA)
        let store = CustomRunnerStore(directoryURL: root.appendingPathComponent("saved"))
        let saved = try store.saveFrames(from: [sourceB, sourceA])
        try require(saved.map(\.lastPathComponent) == ["frame-00.png", "frame-01.png"])
        let firstFrame = try Data(contentsOf: saved[0])
        let secondFrame = try Data(contentsOf: saved[1])
        try require(firstFrame == Data([0x41]), "file name order decides frame order")
        try require(secondFrame == Data([0x42]))
        try require(store.loadFrameURLs() == saved)
        try store.deleteAll()
        try require(store.loadFrameURLs().isEmpty)

        var rejectedSingle = false
        do {
            _ = try store.saveFrames(from: [sourceA])
        } catch CustomRunnerStoreError.invalidFrameCount {
            rejectedSingle = true
        }
        try require(rejectedSingle, "a single frame must be rejected")
    },
    TestCase(name: "Network rate formatter uses decimal unit boundaries") {
        try require(SystemFormatting.formatBytesPerSecond(999) == "999 B/s")
        try require(SystemFormatting.formatBytesPerSecond(1_000) == "1.0 KB/s")
        try require(SystemFormatting.formatBytesPerSecond(1_000_000) == "1.0 MB/s")
    },
]
