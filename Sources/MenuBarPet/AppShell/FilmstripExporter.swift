import AppKit
import Foundation
import MenuBarPetCore

enum FilmstripExportError: LocalizedError {
    case missingOutputDirectory
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingOutputDirectory:
            "--filmstrip の後に出力ディレクトリを指定してください。"
        case let .encodingFailed(name):
            "PNGを書き出せませんでした: \(name)"
        }
    }
}

@MainActor
enum FilmstripExporter {
    private static let lightBackground = NSColor(
        calibratedRed: 0.91,
        green: 0.91,
        blue: 0.92,
        alpha: 1
    )
    private static let darkBackground = NSColor(
        calibratedRed: 0.16,
        green: 0.16,
        blue: 0.17,
        alpha: 1
    )

    // 意味色（labelColor 等）は描画時の周囲のアピアランスで解決されるため、Macのライト/ダーク設定が
    // そのまま出力に混ざる。比較用の書き出しなので aqua に固定して、どのMacでも同じPNGになるようにする。
    static func export(to directoryURL: URL) throws {
        var thrown: Error?
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            do { try writeAll(to: directoryURL) } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    private static func writeAll(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        for character in PetCharacter.allCases {
            for state in PetState.allCases {
                let lightFrames = frames(
                    character: character,
                    state: state,
                    isDarkAppearance: false
                )
                let darkFrames = frames(
                    character: character,
                    state: state,
                    isDarkAppearance: true
                )

                for (index, frame) in lightFrames.enumerated() {
                    let name = String(
                        format: "frame-%@-%@-%02d.png",
                        character.rawValue,
                        state.fileName,
                        index
                    )
                    try writePNG(
                        images: [frame],
                        background: lightBackground,
                        pointSize: PetRenderer.pointSize,
                        name: name,
                        directoryURL: directoryURL
                    )
                }

                let stripSize = NSSize(
                    width: PetRenderer.pointSize.width * 12,
                    height: PetRenderer.pointSize.height
                )
                for (appearance, frames, background) in [
                    ("light", lightFrames, lightBackground),
                    ("dark", darkFrames, darkBackground),
                ] {
                    try writePNG(
                        images: frames,
                        background: background,
                        pointSize: stripSize,
                        name: "strip-\(character.rawValue)-\(state.fileName)-\(appearance).png",
                        directoryURL: directoryURL
                    )
                }
            }
        }
    }

    // 自作ランナーはユーザーのPNG頼みなので、書き出し用に単色のダミーコマを合成する。
    private static let placeholderRunnerFrames: [NSImage] = [
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.85, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.40, alpha: 1),
    ].map { color in
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private static func frames(
        character: PetCharacter,
        state: PetState,
        isDarkAppearance: Bool
    ) -> [NSImage] {
        let customFrames = character == .custom ? placeholderRunnerFrames : []
        return (0..<12).map { index in
            PetRenderer.render(
                character: character,
                state: state,
                phase: Double(index) / 12,
                wheelPhase: Double(index) / 12,
                isDarkAppearance: isDarkAppearance,
                reduceMotion: false,
                customFrames: customFrames
            )
        }
    }

    private static func writePNG(
        images: [NSImage],
        background: NSColor,
        pointSize: NSSize,
        name: String,
        directoryURL: URL
    ) throws {
        guard let data = PetRenderer.pngData(
            images: images,
            backgroundColor: background,
            pointSize: pointSize
        ) else { throw FilmstripExportError.encodingFailed(name) }
        try data.write(to: directoryURL.appendingPathComponent(name), options: .atomic)
    }
}
