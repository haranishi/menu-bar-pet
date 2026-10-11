import CMbpCore
import Foundation

public struct RustCPUSampler {
    private var core = MbpCpuSampler()
    public init() {}
    public mutating func readUsage() -> Double? {
        let value = mbp_cpu_sample(&core)
        return value.isFinite ? value : nil
    }
    public mutating func reset() { core = MbpCpuSampler() }
}

public final class RustNetworkSampler {
    private let core: OpaquePointer?
    public init() { core = mbp_network_new() }
    deinit { mbp_network_free(core) }
    public func sample(uptime: Double) -> (received: Double, sent: Double) {
        let sample = mbp_network_sample(core, uptime)
        return (sample.received, sample.sent)
    }
    public static func memoryUsagePercentage() -> Int { Int(mbp_memory_usage()) }
}
