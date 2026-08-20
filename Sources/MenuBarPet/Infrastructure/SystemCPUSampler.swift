import Darwin
import Foundation

@MainActor
final class SystemCPUSampler: CPUSampling {
    private var previousBusy: UInt64?
    private var previousTotal: UInt64?

    func readUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer {
            previousBusy = busy
            previousTotal = total
        }
        guard let previousBusy, let previousTotal, total > previousTotal else { return nil }

        let busyDelta = busy >= previousBusy ? busy - previousBusy : 0
        let totalDelta = total - previousTotal
        return totalDelta == 0 ? nil : Double(busyDelta) / Double(totalDelta) * 100
    }

    func reset() {
        previousBusy = nil
        previousTotal = nil
    }
}
