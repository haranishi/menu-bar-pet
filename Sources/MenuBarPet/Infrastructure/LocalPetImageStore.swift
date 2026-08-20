import AppKit
import Foundation
import ImageIO

enum PetImageStoreError: LocalizedError {
    case unsupportedFormat
    case fileTooLarge
    case dimensionsTooLarge
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "PNG、JPEG、HEICの画像を選んでください。"
        case .fileTooLarge: "画像は20MB以下にしてください。"
        case .dimensionsTooLarge: "画像の縦横は8192px以下にしてください。"
        case .unreadableImage: "画像を読み込めませんでした。"
        case .encodingFailed: "表示用画像を作成できませんでした。"
        }
    }
}

@MainActor
final class LocalPetImageStore: PetImageStoring {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("com.hara.MenuBarPet/pets/current", isDirectory: true)
    }

    func loadProcessedImage() -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent("processed.png"))
    }

    func importImage(from sourceURL: URL) throws -> Data {
        let allowedExtensions = ["png", "jpg", "jpeg", "heic"]
        guard allowedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw PetImageStoreError.unsupportedFormat
        }
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20 * 1_024 * 1_024 else {
            throw PetImageStoreError.fileTooLarge
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw PetImageStoreError.unreadableImage }
        guard width <= 8_192, height <= 8_192 else { throw PetImageStoreError.dimensionsTooLarge }
        guard let image = NSImage(contentsOf: sourceURL) else { throw PetImageStoreError.unreadableImage }

        let maxSide: CGFloat = 512
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let outputSize = NSSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width.rounded()),
            pixelsHigh: Int(outputSize.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw PetImageStoreError.encodingFailed }
        bitmap.size = outputSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()
        image.draw(in: NSRect(origin: .zero, size: outputSize),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PetImageStoreError.encodingFailed
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(contentsOf: sourceURL).write(to: directoryURL.appendingPathComponent("original.bin"), options: .atomic)
        try png.write(to: directoryURL.appendingPathComponent("processed.png"), options: .atomic)
        return png
    }

    func deleteImage() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }
}
