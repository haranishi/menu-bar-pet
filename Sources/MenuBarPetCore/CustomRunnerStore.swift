import Foundation

public enum CustomRunnerStoreError: LocalizedError, Equatable {
    case invalidFrameCount
    case pngOnly

    public var errorDescription: String? {
        switch self {
        case .invalidFrameCount: "PNG画像を2〜24枚選んでください。"
        case .pngOnly: "PNG画像だけを選んでください。"
        }
    }
}

public struct CustomRunnerStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    public static func applicationSupportStore() -> CustomRunnerStore {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let identifier = Bundle.main.bundleIdentifier ?? "MenuBarPet"
        return CustomRunnerStore(
            directoryURL: applicationSupport
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("CustomRunner", isDirectory: true)
        )
    }

    public func loadFrameURLs() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    public func saveFrames(from sourceURLs: [URL]) throws -> [URL] {
        guard (2...24).contains(sourceURLs.count) else {
            throw CustomRunnerStoreError.invalidFrameCount
        }
        guard sourceURLs.allSatisfy({ $0.pathExtension.lowercased() == "png" }) else {
            throw CustomRunnerStoreError.pngOnly
        }

        let sortedSources = sourceURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let fileManager = FileManager.default
        let parentURL = directoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let stagingURL = parentURL.appendingPathComponent(
            ".CustomRunner-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        do {
            for (index, sourceURL) in sortedSources.enumerated() {
                let destination = stagingURL.appendingPathComponent(
                    String(format: "frame-%02d.png", index)
                )
                try fileManager.copyItem(at: sourceURL, to: destination)
            }
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.moveItem(at: stagingURL, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
        return loadFrameURLs()
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try FileManager.default.removeItem(at: directoryURL)
    }
}
