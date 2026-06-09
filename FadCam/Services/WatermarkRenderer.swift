import UIKit
import AVFoundation
import CoreImage
import CoreGraphics
import Foundation
import OSLog

private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "watermark")

/// Builds a watermarked CIImage positioned in landscape buffer coordinates
/// so that after AVAssetWriter's rotation transform, the watermark
/// appears at the correct corner in the final portrait video.
///
/// ## Coordinate Systems
/// - **CIImage**: origin at bottom-left.  CIImage(cvPixelBuffer:) puts (0,0) at bottom-left.
/// - **Encoded (AVAssetWriter)**: origin at top-left.  This is what the writer's
///   `transform` property maps FROM.
/// - **Display (portrait video)**: origin at top-left.  This is what the player shows.
///
/// ## Back Camera
/// Writer transform = rotate(+π/2) CW.
/// Mapping: CI (0,0) → portrait top-left, CI (W,0) → portrait bottom-left,
///          CI (0,H) → portrait top-right, CI (W,H) → portrait bottom-right.
///
/// ## Front Camera
/// Writer transform = scaleX(-1).rotated(by: -π/2), which equals (x,y)→(y,x).
/// Self-inverse.  Mapping: CI (0,H) → portrait top-left.
enum WatermarkRenderer {

    private static let padding: CGFloat = 24

    // MARK: - Public API

    /// Composites a watermark onto the given pixel buffer.
    /// - Parameters:
    ///   - settings: Watermark configuration (text, size, opacity, corner).
    ///   - pixelBuffer: The raw camera frame in landscape orientation.
    ///   - cameraPosition: `.back` or `.front` — determines pre-rotation direction.
    /// - Returns: A new CIImage with the watermark composited, or nil on failure.
    static func buildCompositedImage(settings: WatermarkSettings,
                                      from pixelBuffer: CVPixelBuffer,
                                      cameraPosition: AVCaptureDevice.Position) -> CIImage? {
        guard settings.enabled, !settings.text.isEmpty else { return nil }

        let background = CIImage(cvPixelBuffer: pixelBuffer)
        let ext = background.extent

        guard let wmCG = renderTextCG(settings: settings) else { return nil }
        var wm = CIImage(cgImage: wmCG)
        let textSize = wm.extent.size  // (tw, th) — width and height of unrotated text

        // Build the combined transform: move anchor to origin → pre-rotate → translate to landscape position
        let transform = watermarkTransform(
            for: settings.corner,
            textSize: textSize,
            landscapeExtent: ext,
            cameraPosition: cameraPosition
        )
        wm = wm.transformed(by: transform)

        guard let filter = CIFilter(name: "CISourceOverCompositing") else {
            log.error("CISourceOverCompositing filter not available")
            return nil
        }
        filter.setValue(wm, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)

        guard let result = filter.outputImage?.cropped(to: ext) else {
            log.error("Compositing filter returned nil output")
            return nil
        }
        return result
    }

    // MARK: - Text Rendering

    /// Renders the watermark text into a CGImage using UIKit.
    /// The resulting image has the text rendered horizontally with padding.
    private static func renderTextCG(settings: WatermarkSettings) -> CGImage? {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: settings.fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(settings.opacity)),
            .paragraphStyle: paragraphStyle
        ]
        let attrStr = NSAttributedString(string: settings.text, attributes: attrs)
        let textSize = attrStr.size()
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            attrStr.draw(at: CGPoint(x: padding, y: padding))
        }.cgImage
    }

    // MARK: - Transform Building

    /// Builds the full CGAffineTransform to apply to the watermark CIImage
    /// so that it appears correctly in the final portrait video.
    ///
    /// Uses center-based anchoring: translates the text center to the origin,
    /// pre-rotates so text reads correctly after the writer's rotation,
    /// then translates to the correct landscape position.
    ///
    /// ## Why +π/2 for back camera (not the inverse -π/2)?
    /// The writer transform is +π/2 in **encoded (y-down)** coordinates.
    /// Because CIImage uses **y-up** coordinates, the writer's effect in CI
    /// is (x,y) → (y,-x). To cancel this: we need a CI pre-rotation that
    /// maps rightward (1,0) to upward (0,1), which is +π/2 in CI.
    /// The direct matrix inverse would be -π/2, which maps (1,0)→(0,-1)
    /// and produces leftward text in portrait — exactly the reported bug.
    private static func watermarkTransform(
        for corner: WatermarkSettings.Corner,
        textSize: CGSize,
        landscapeExtent: CGRect,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGAffineTransform {
        let tw = textSize.width
        let th = textSize.height
        let lw = landscapeExtent.width
        let lh = landscapeExtent.height

        // Step 1: Move center of text to origin
        let toOrigin = CGAffineTransform(translationX: -tw / 2, y: -th / 2)

        // Step 2: Pre-rotation — inverse of the writer's transform
        // Back camera writer = rotate(+π/2) CW in y-down → CI pre-rotate +π/2 CCW.
        // Front camera writer = (x,y)→(y,x) swap in y-down → same swap as pre-transform.
        let preRotation: CGAffineTransform
        if cameraPosition == .front {
            preRotation = CGAffineTransform(scaleX: -1, y: 1).rotated(by: -.pi / 2)
        } else {
            preRotation = CGAffineTransform(rotationAngle: .pi / 2)
        }

        // Concatenate: toOrigin applied FIRST, then preRotation
        // A.concatenating(B) = B·A, applies A first then B
        // So toOrigin.concatenating(preRotation) = preRotation·toOrigin = toOrigin→preRotation
        let rotated = toOrigin.concatenating(preRotation)

        // After pre-rotation, size becomes: width=th, height=tw (dimensions swap)
        let rotatedW = th
        let rotatedH = tw

        // Step 3: Translate center in the final landscape coordinate space.
        // translatedBy(x:y:) would apply the offset in the already-rotated
        // local basis, moving the watermark outside the video buffer.
        let (cx, cy) = landscapeCenter(
            for: corner,
            rotatedWidth: rotatedW,
            rotatedHeight: rotatedH,
            landscapeW: lw,
            landscapeH: lh,
            cameraPosition: cameraPosition
        )
        let landscapeTranslation = CGAffineTransform(translationX: cx, y: cy)
        return rotated.concatenating(landscapeTranslation)
    }

    // MARK: - Landscape Center Positioning

    /// Returns the center position in CIImage landscape buffer (bottom-left origin)
    /// where the pre-rotated watermark should be centered so that after the writer's
    /// rotation transform, the watermark appears at the desired corner with padding.
    ///
    /// The rotated text has size (rotatedW × rotatedH) where rotatedW = original height,
    /// rotatedH = original width (dimensions swap after 90° pre-rotation).
    private static func landscapeCenter(
        for corner: WatermarkSettings.Corner,
        rotatedWidth rw: CGFloat,
        rotatedHeight rh: CGFloat,
        landscapeW lw: CGFloat,
        landscapeH lh: CGFloat,
        cameraPosition: AVCaptureDevice.Position
    ) -> (CGFloat, CGFloat) {

        if cameraPosition == .front {
            // Writer T = (x,y)→(y,x), self-inverse.
            // CI (0, lh) = landscape top-left     → portrait top-left.
            // CI (0, 0)  = landscape bottom-left  → portrait top-right.
            // CI (lw, lh)= landscape top-right    → portrait bottom-left.
            // CI (lw, 0) = landscape bottom-right → portrait bottom-right.
            switch corner {
            case .topLeading:
                return (padding + rw / 2, lh - padding - rh / 2)
            case .topTrailing:
                return (padding + rw / 2, padding + rh / 2)
            case .bottomLeading:
                return (lw - padding - rw / 2, lh - padding - rh / 2)
            case .bottomTrailing:
                return (lw - padding - rw / 2, padding + rh / 2)
            }
        } else {
            // Writer T = rotate(+π/2) CW.
            // CI (0, 0)  = landscape bottom-left  → portrait top-left.
            // CI (lw, 0) = landscape bottom-right → portrait bottom-left.
            // CI (0, lh) = landscape top-left     → portrait top-right.
            // CI (lw, lh)= landscape top-right    → portrait bottom-right.
            switch corner {
            case .topLeading:
                return (padding + rw / 2, padding + rh / 2)
            case .topTrailing:
                return (padding + rw / 2, lh - padding - rh / 2)
            case .bottomLeading:
                return (lw - padding - rw / 2, padding + rh / 2)
            case .bottomTrailing:
                return (lw - padding - rw / 2, lh - padding - rh / 2)
            }
        }
    }
}
