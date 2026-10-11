import AppKit

/// The native status button handles clicks, selection and accessibility.
/// This view changes pixels without asking AppKit to resize the status item every frame.
@MainActor
final class StatusImageView: NSView {
    var onAppearanceChanged: (() -> Void)?
    private let drawingLayer = CALayer()
    private var imageSize = NSSize.zero
    private weak var displayedImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        drawingLayer.contentsScale = 2
        drawingLayer.contentsGravity = .resize
        layer?.addSublayer(drawingLayer)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }

    func display(_ image: NSImage) {
        guard displayedImage !== image else { return }
        displayedImage = image
        imageSize = image.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawingLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        placeImage()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeImage()
        CATransaction.commit()
    }

    private func placeImage() {
        drawingLayer.frame = CGRect(
            x: ((bounds.width - imageSize.width) / 2).rounded(),
            y: ((bounds.height - imageSize.height) / 2).rounded(),
            width: imageSize.width, height: imageSize.height
        )
    }
}
