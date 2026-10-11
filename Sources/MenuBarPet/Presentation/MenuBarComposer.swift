import AppKit
import MenuBarPetCore

/// ペット画像と数値テキストを1枚の `NSImage` に合成する。
///
/// `NSStatusBarButton` の `attributedTitle` に 2 行を渡すと、ボタンが確保する描画領域が
/// 22pt の全高を使えず、上段のグリフ上端が切れた（2026-09-16 実機）。
/// ボタンに文字を描かせるのをやめ、こちらでベースラインを決めて 22pt に確実に収める。
/// **`PetRenderer` には一切触らない**（キャラの絵と大きさは従来どおり）。
@MainActor
enum MenuBarComposer {
    typealias Layout = MenuBarReadout.Layout

    static let height = CGFloat(Layout.height)
    static let petSlotWidth = CGFloat(Layout.petSlotWidth)

    static let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(Layout.fontSize), weight: .medium)

    /// いちばん長い行の幅。等幅数字なので桁数が同じなら幅も揃う。
    static func textWidth(rows: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return rows
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
    }

    static func width(rows: [String]) -> CGFloat {
        CGFloat(Layout.width(textWidth: Double(textWidth(rows: rows)), rowCount: rows.count))
    }

    /// 行が無くても 44pt の画像を返す（CPU モード＝従来のステータス項目の幅と同じ）。
    /// ステータス項目は `variableLength` なので、この画像の幅がそのまま項目の幅になる。
    private static var cachedRows: [String] = []
    private static var cachedDark = false
    private static var composed: [ObjectIdentifier: (pet: NSImage, image: NSImage)] = [:]
    private static var slots = Array<ObjectIdentifier?>(repeating: nil, count: 96)
    private static var nextSlot = 0
    static var cachedImageCount: Int { composed.count }

    static func compose(pet: NSImage, rows: [String], isDark: Bool) -> NSImage {
        if rows != cachedRows || isDark != cachedDark {
            composed.removeAll(keepingCapacity: true)
            slots = Array(repeating: nil, count: 96)
            nextSlot = 0
            cachedRows = rows
            cachedDark = isDark
        }
        let key = ObjectIdentifier(pet)
        if let cached = composed[key] { return cached.image }
        let overlay = textOverlay(rows: rows, isDark: isDark)
        let size = overlay?.size ?? NSSize(width: petSlotWidth, height: height)
        guard let bitmap = makeBitmap(pointSize: size) else { return pet }
        withContext(bitmap) { context in
            context.clear(CGRect(origin: .zero, size: size))
            context.saveGState()
            let petSize = pet.size
            pet.draw(
                in: NSRect(
                    x: ((petSlotWidth - petSize.width) / 2).rounded(),
                    y: ((height - petSize.height) / 2).rounded(),
                    width: petSize.width, height: petSize.height
                ),
                from: .zero, operation: .sourceOver, fraction: 1
            )
            context.restoreGState()
            overlay?.draw(
                in: NSRect(origin: .zero, size: size), from: .zero,
                operation: .sourceOver, fraction: 1
            )
        }
        let output = NSImage(size: size)
        output.addRepresentation(bitmap)
        output.isTemplate = false
        verifyTextOnce(output, rows: rows)
        if let previous = slots[nextSlot] { composed.removeValue(forKey: previous) }
        slots[nextSlot] = key
        nextSlot = (nextSlot + 1) % slots.count
        composed[key] = (pet, output)
        return output
    }

    private struct TextCache {
        let rows: [String]
        let isDark: Bool
        let image: NSImage
    }
    private static var cachedText: TextCache?

    /// Fonts, measurement, appearance resolution and glyph drawing run only when the text changes.
    private static func textOverlay(rows: [String], isDark: Bool) -> NSImage? {
        guard !rows.isEmpty else { return nil }
        if let cachedText, cachedText.rows == rows, cachedText.isDark == isDark {
            return cachedText.image
        }
        let size = NSSize(width: width(rows: rows), height: height)
        guard let bitmap = makeBitmap(pointSize: size) else { return nil }
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            let textColor = resolvedTextColor(isDark: isDark)
            withContext(bitmap) { context in
                context.clear(CGRect(origin: .zero, size: size))
                context.textMatrix = .identity
                context.setTextDrawingMode(.fill)
                context.setFillColor(textColor.cgColor)
                drawRows(rows, color: textColor)
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        cachedText = TextCache(rows: rows, isDark: isDark, image: image)
        return image
    }

    /// `labelColor` を不透明寄りの具体色まで落とす。動的カタログ色のまま使うと、
    /// 解決先が描画時の外観に左右される。
    private static func resolvedTextColor(isDark: Bool) -> NSColor {
        let fallback = isDark ? NSColor.white : NSColor.black
        guard let rgb = NSColor.labelColor.usingColorSpace(.sRGB) else { return fallback }
        // labelColor は半透明。メニューバーで薄くなりすぎないよう下限を設ける。
        return rgb.alphaComponent < 0.6 ? rgb.withAlphaComponent(0.9) : rgb
    }

    /// 1プロセスに1回だけ、文字が本当に描けたか確かめる。
    /// 消えていたら Console に痕跡を残す（実機で黙って消え、原因が追えなかったため）。
    private static var hasVerifiedText = false

    private static func verifyTextOnce(_ image: NSImage, rows: [String]) {
        guard !hasVerifiedText, !rows.isEmpty else { return }
        hasVerifiedText = true
        if textClearance(image) == nil {
            NSLog("MenuBarPet: メニューバーの数値が1画素も描かれませんでした rows=%@", rows)
        }
    }

    /// ベースラインを指定して1行ずつ描く。
    ///
    /// CoreText の `CTLineDraw` は `CGContext.textMatrix` に依存し、実機で文字が1画素も出ない
    /// 事象が起きた（2026-09-16・CLI では再現せず）。AppKit の描画はアプリの他の描画と同じ経路で
    /// テキスト行列に依存しないので、こちらを本筋にする。`draw(at:)` の原点は行ボックスの左下＝
    /// ベースライン＋descender（負値）なので、そのぶん下げれば狙ったベースラインに乗る。
    private static func drawRows(_ rows: [String], color: NSColor) {
        let face = font
        let baselines = Layout.baselines(rowCount: rows.count)
        let originX = CGFloat(Layout.textOriginX())
        let attributes: [NSAttributedString.Key: Any] = [
            .font: face,
            .foregroundColor: color,
        ]
        for (row, baseline) in zip(rows, baselines) {
            NSAttributedString(string: row, attributes: attributes)
                .draw(at: NSPoint(x: originX, y: CGFloat(baseline) + face.descender))
        }
    }

    private static func makeBitmap(pointSize: NSSize) -> NSBitmapImageRep? {
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(pointSize.width * CGFloat(scale))),
            pixelsHigh: Int(ceil(pointSize.height * CGFloat(scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = pointSize
        return bitmap
    }

    private static func withContext(_ bitmap: NSBitmapImageRep, draw: (CGContext) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        graphics.shouldAntialias = true
        draw(graphics.cgContext)
        graphics.flushGraphics()
    }

    static func pngData(_ image: NSImage) -> Data? {
        image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .first?
            .representation(using: .png, properties: [:])
    }

    /// 文字が上下で切れていないことを数値で示すための計測。テキスト側だけを見る。
    /// 返り値は @2x ピクセル単位の (上の余白, 下の余白)。文字が無ければ nil。
    static func textClearance(_ image: NSImage) -> (top: Int, bottom: Int)? {
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first
        else { return nil }
        let scale = bitmap.pixelsHigh / Int(image.size.height)
        let firstTextColumn = Int(CGFloat(Layout.textOriginX())) * scale
        guard firstTextColumn < bitmap.pixelsWide else { return nil }

        var topmost: Int?
        var bottommost: Int?
        for y in 0..<bitmap.pixelsHigh {
            var hasInk = false
            for x in firstTextColumn..<bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    hasInk = true
                    break
                }
            }
            if hasInk {
                if topmost == nil { topmost = y }
                bottommost = y
            }
        }
        guard let topmost, let bottommost else { return nil }
        return (topmost, bitmap.pixelsHigh - 1 - bottommost)
    }
}
