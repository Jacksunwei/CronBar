import AppKit

/// App imagery: the full-color icon (for the dropdown header) and a monochrome
/// template glyph (for the menu bar, which the system tints for light/dark).
enum IconAssets {
    /// Full-color app icon (squircle + clock) loaded from bundled artwork.
    static let appIcon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    /// Monochrome, template clock glyph for the menu bar. Drawn to echo the app
    /// icon's clock (thin ring + two hands + center hub). Marked as a template so
    /// macOS renders it correctly in light and dark menu bars.
    static let menuBar: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.width
            let center = CGPoint(x: s / 2, y: s / 2)
            let r = s * 0.40
            let lw = max(1, s * 0.11)

            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(NSColor.black.cgColor)   // template: tinted by system
            cg.setFillColor(NSColor.black.cgColor)
            cg.setLineWidth(lw)

            // Ring.
            cg.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))

            // Hands (~10:08, matching the icon).
            func hand(angleDeg: CGFloat, length: CGFloat) {
                let a = (90 - angleDeg) * .pi / 180
                cg.move(to: center)
                cg.addLine(to: CGPoint(x: center.x + cos(a) * length, y: center.y + sin(a) * length))
                cg.strokePath()
            }
            hand(angleDeg: 300, length: r * 0.50)   // hour
            hand(angleDeg: 60, length: r * 0.66)    // minute

            // Center hub.
            let hub = lw * 0.6
            cg.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub))
            return true
        }
        image.isTemplate = true
        return image
    }()
}
