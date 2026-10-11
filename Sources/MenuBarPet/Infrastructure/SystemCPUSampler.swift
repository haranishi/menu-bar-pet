import MenuBarPetCore

@MainActor
final class SystemCPUSampler: CPUSampling {
    private var sampler = RustCPUSampler()
    func readUsage() -> Double? { sampler.readUsage() }
    func reset() { sampler.reset() }
}
