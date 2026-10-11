import MenuBarPetCore

let petStateMachineTests: [TestCase] = [
    TestCase(name: "CPU usage maps to all five states") {
        let mappings: [(Double, PetState)] = [
            (5, .resting), (35, .normal), (60, .running), (80, .sweating), (95, .onFire),
        ]
        for (usage, expected) in mappings {
            try require(PetStateMachine.classify(usage, thresholds: Sensitivity.standard.thresholds) == expected)
        }
    },
    TestCase(name: "Upward transition requires three samples") {
        var machine = PetStateMachine(alpha: 1)
        let states = (0..<3).map { _ in machine.ingest(80, sensitivity: .standard).state }
        try require(states == [.normal, .normal, .sweating])
    },
    TestCase(name: "Downward transition requires five samples") {
        var machine = PetStateMachine(alpha: 1)
        _ = (0..<3).map { _ in machine.ingest(80, sensitivity: .standard) }
        let states = (0..<5).map { _ in machine.ingest(40, sensitivity: .standard).state }
        try require(states == [.sweating, .sweating, .sweating, .sweating, .normal])
    },
    TestCase(name: "Raw CPU usage is clamped") {
        var machine = PetStateMachine(alpha: 1)
        try require(machine.ingest(-10, sensitivity: .standard).usage == 0)
        try require(machine.ingest(130, sensitivity: .standard).usage == 100)
    },
]
