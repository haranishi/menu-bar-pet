import CMbpCore
import Foundation

enum RustUsageBridge {
    private struct Parsed: Decodable {
        struct Window: Decodable {
            let label: String
            let used: Double
            let resets: Double?
            let duration: Double?
        }
        let windows: [Window]
        let extras: [String: String]
        let observedText: String?
        let noteText: String?
        let note: String?
    }
    static func parse(
        _ data: Data, provider: AIUsageProvider, observedAt: Date,
        profileName: String, sourcePath: String
    ) -> AIUsageSnapshot? {
        let buffer = data.withUnsafeBytes { bytes in
            mbp_usage_parse(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, provider == .claudeCode ? 0 : 1)
        }
        defer { mbp_buffer_free(buffer) }
        guard let pointer = buffer.data, buffer.len > 0,
              let parsed = try? JSONDecoder().decode(Parsed.self, from: Data(bytes: pointer, count: buffer.len))
        else { return nil }
        let timestamps = provider == .codex ? ISO8601TimestampParser() : nil
        var extras = parsed.extras
        if extras[AIUsageSnapshot.rateLimitReachedTypeKey] != nil {
            let noteAt = timestamps?.date(from: parsed.noteText) ?? observedAt
            extras[AIUsageSnapshot.noteObservedAtKey] = timestamps?.string(from: noteAt)
        }
        return AIUsageSnapshot(
            provider: provider, profileName: profileName,
            windows: parsed.windows.map { AIUsageWindow(
                label: $0.label, usedPercentage: $0.used,
                resetsAt: $0.resets.map(Date.init(timeIntervalSince1970:)), durationMinutes: $0.duration
            ) },
            observedAt: timestamps?.date(from: parsed.observedText)
                ?? timestamps?.date(from: parsed.noteText) ?? observedAt,
            note: parsed.note, sourcePath: sourcePath, extras: extras
        )
    }
    static func readTail(of url: URL, maxBytes: Int) -> String? {
        guard maxBytes > 0 else { return nil }
        let path = Array(url.path.utf8)
        let buffer = path.withUnsafeBufferPointer { mbp_read_tail($0.baseAddress, $0.count, maxBytes) }
        defer { mbp_buffer_free(buffer) }
        guard let pointer = buffer.data else { return nil }
        return String(data: Data(bytes: pointer, count: buffer.len), encoding: .utf8)
    }
}
