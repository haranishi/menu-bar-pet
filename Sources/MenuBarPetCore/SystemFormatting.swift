import Foundation

public enum SystemFormatting {
    public static func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond.isFinite ? bytesPerSecond : 0, 0)
        if value < 1_000 {
            return "\(Int(value.rounded())) B/s"
        }
        if value < 1_000_000 {
            return String(format: "%.1f KB/s", value / 1_000)
        }
        if value < 1_000_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }
        return String(format: "%.1f GB/s", value / 1_000_000_000)
    }

    public static func formatAvailableBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}
