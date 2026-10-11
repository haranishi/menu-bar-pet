import AppKit
import Foundation
import MenuBarPetCore

/// GUI を立ち上げずにメニューバーの見た目を PNG へ出す。
///
/// メニューバーの中身は実機を撮らないと分からない、という状態だと文字の欠けを見逃す
/// （実際に見逃した）。実データ 1 枚と、決定的な固定入力 4 ケースを light/dark で書き出し、
/// 文字の上下の余白をピクセルで数えられるようにしておく。
@MainActor
enum MenuBarSnapshotExporter {
    private struct Case {
        let name: String
        let rows: [String]
        let state: PetState
        /// 一時停止中はアプリが `reduceMotion: true` でペットを描く。文字が消えた実機はこの経路だった。
        var reduceMotion = false
        /// アプリはペット描画を外観で包まない。CLI だけ包むと差分が出るので再現用に切り替える。
        var wrapsPetAppearance = true
    }

    private static let fixtures: [Case] = [
        Case(name: "fixture-full", rows: ["Claude 100  21", "Codex  上限"], state: .onFire),
        Case(name: "fixture-dashes", rows: ["Claude  --  --", "Codex   17  88"], state: .running),
        Case(name: "fixture-single", rows: ["Codex   17  88"], state: .normal),
        Case(name: "fixture-empty", rows: [], state: .normal),
    ]

    /// アプリと同じ条件（一時停止＝reduceMotion、外観で包まないペット描画）。
    private static func appLikeCase(rows: [String], state: PetState) -> Case {
        Case(
            name: "applike",
            rows: rows,
            state: state,
            reduceMotion: true,
            wrapsPetAppearance: false
        )
    }

    static func export(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let live = liveCase()
        var report: [String] = []
        var missingText: [String] = []
        for entry in fixtures + [live, appLikeCase(rows: live.rows, state: live.state)] {
            for isDark in [false, true] {
                let name = "\(entry.name)-\(isDark ? "dark" : "light").png"
                let image = compose(entry: entry, isDark: isDark)
                guard let data = MenuBarComposer.pngData(image) else { continue }
                try data.write(to: directoryURL.appendingPathComponent(name), options: .atomic)
                report.append(describe(name: name, image: image, rows: entry.rows))
                if !entry.rows.isEmpty, MenuBarComposer.textClearance(image) == nil {
                    missingText.append(name)
                }

                // 透過のままだとビューアでは白地に白文字で何も見えない。
                // 実機写真と同じ条件で目視できるよう、背景を敷いて 4 倍に伸ばした控えも置く。
                if let preview = MenuBarComposer.pngData(
                    magnified(image, background: isDark ? .black : .white, scale: 4)
                ) {
                    try preview.write(
                        to: directoryURL.appendingPathComponent("preview-\(name)"),
                        options: .atomic
                    )
                }
            }
        }

        print("menubar snapshots -> \(directoryURL.path)")
        report.forEach { print($0) }
        // 文字が1画素も無いケースがあれば落とす（実機で消えたのを CLI が見逃さないように）。
        guard missingText.isEmpty else {
            fputs("MenuBarPet: 文字が描かれていません: \(missingText.joined(separator: ", "))\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    /// 実データ 1 枚。キャラの状態も駆動値から決めて、実際に出るはずの見た目に寄せる。
    private static func liveCase() -> Case {
        let repository = AIUsageRepository()
        repository.refresh()
        let enabled = Set(AIUsageProvider.allCases)
        let now = Date()
        let rows = MenuBarReadout.rows(snapshots: repository.snapshots, enabled: enabled, now: now)
        let drive = AIUsageAggregator.driveValue(
            snapshots: repository.snapshots,
            enabled: enabled,
            now: now
        ) ?? 0
        return Case(
            name: "menubar",
            rows: rows,
            state: PetStateMachine.classify(drive, thresholds: Sensitivity.standard.thresholds)
        )
    }

    private static func compose(entry: Case, isDark: Bool) -> NSImage {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            ?? NSAppearance.currentDrawing()
        func renderPet() -> NSImage {
            PetRenderer.render(
                character: .shibaInu,
                state: entry.state,
                phase: 0,
                wheelPhase: 0,
                isDarkAppearance: isDark,
                reduceMotion: entry.reduceMotion
            )
        }
        var pet = NSImage(size: PetRenderer.pointSize)
        if entry.wrapsPetAppearance {
            appearance.performAsCurrentDrawingAppearance { pet = renderPet() }
        } else {
            pet = renderPet()
        }
        return MenuBarComposer.compose(pet: pet, rows: entry.rows, isDark: isDark)
    }

    /// 背景を敷いて整数倍に拡大する（補間なし＝ピクセルの欠けがそのまま見える）。
    private static func magnified(_ image: NSImage, background: NSColor, scale: Int) -> NSImage {
        let size = NSSize(
            width: image.size.width * CGFloat(scale),
            height: image.size.height * CGFloat(scale)
        )
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let graphics = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = graphics
            graphics.imageInterpolation = .none
            background.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(
                in: NSRect(origin: .zero, size: size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            graphics.flushGraphics()
        }
        let output = NSImage(size: size)
        output.addRepresentation(bitmap)
        return output
    }

    private static func describe(name: String, image: NSImage, rows: [String]) -> String {
        let size = "\(Int(image.size.width))x\(Int(image.size.height))pt"
        guard !rows.isEmpty else {
            return "  \(name)  \(size)  (pet only, no text)"
        }
        guard let clearance = MenuBarComposer.textClearance(image) else {
            return "  \(name)  \(size)  WARNING: no text pixels found"
        }
        let verdict = clearance.top >= 2 && clearance.bottom >= 2 ? "ok" : "TIGHT"
        return "  \(name)  \(size)  top gap=\(clearance.top)px bottom gap=\(clearance.bottom)px"
            + " @2x  \(verdict)  rows=\(rows.count)"
    }
}
