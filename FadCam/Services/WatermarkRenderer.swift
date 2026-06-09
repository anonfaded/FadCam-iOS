import UIKit
import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
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
/// Writer transform = rotate(+π/2). After the player normalizes its negative
/// bounds, the same transform and corner mapping applies to both cameras.
enum WatermarkRenderer {

    private static let padding: CGFloat = 8

    // MARK: - Public API

    /// Builds the encoded frame after applying camera-only mirroring and then
    /// compositing an optional watermark.
    /// - Parameters:
    ///   - settings: Watermark configuration (text, size, opacity, corner).
    ///   - pixelBuffer: The raw camera frame in landscape orientation.
    ///   - mirrorCameraForPortraitDisplay: Mirrors camera pixels left/right in
    ///     the final portrait video without mirroring the watermark.
    /// - Returns: The processed camera frame, or nil if compositing fails.
    static func buildOutputImage(settings: WatermarkSettings,
                                 from pixelBuffer: CVPixelBuffer,
                                 mirrorCameraForPortraitDisplay: Bool) -> CIImage? {
        var background = CIImage(cvPixelBuffer: pixelBuffer)
        let ext = background.extent

        // A raw vertical flip becomes a left/right mirror after the writer's
        // 90-degree portrait rotation.
        if mirrorCameraForPortraitDisplay {
            let rawVerticalFlip = CGAffineTransform(
                a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ext.height
            )
            background = background.transformed(by: rawVerticalFlip).cropped(to: ext)
        }

        guard settings.isWatermarkShown else { return background }

        let watermarkAttrStr = settings.buildWatermarkAttributedText(fontSize: settings.fontSize)
        guard watermarkAttrStr.length > 0,
              let wmCG = renderAttributedText(watermarkAttrStr,
                                               opacity: settings.opacity,
                                               shadow: settings.shadowEnabled) else { return nil }
        var wm = CIImage(cgImage: wmCG)
        let textSize = wm.extent.size  // (tw, th) — width and height of unrotated text

        // Build the combined transform: move anchor to origin → pre-rotate → translate to landscape position
        let transform = watermarkTransform(
            for: settings.corner,
            textSize: textSize,
            landscapeExtent: ext
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

    /// Composites the watermark onto a FadShot photo, applying the necessary
    /// rotation so the output is always portrait-oriented.
    static func buildWatermarkedPhoto(jpegData: Data, settings: WatermarkSettings, cameraPosition: AVCaptureDevice.Position) -> Data? {
        guard settings.isWatermarkShown else { return jpegData }
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let rawCG = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            log.error("Photo watermark: failed to decode JPEG data")
            return jpegData
        }

        // Rotate the raw camera image to portrait orientation.
        // Back camera delivers landscape-right; front camera delivers landscape-left.
        let rawCI = CIImage(cgImage: rawCG)
        let portraitCI: CIImage
        if cameraPosition == .front {
            portraitCI = rawCI.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        } else {
            portraitCI = rawCI.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
        }
        let ext = portraitCI.extent
        let w = ext.width
        let h = ext.height
        let background = portraitCI

        let watermarkAttrStr = settings.buildWatermarkAttributedText(fontSize: settings.fontSize)
        guard watermarkAttrStr.length > 0,
              let wmCG = renderAttributedText(watermarkAttrStr,
                                               opacity: settings.opacity,
                                               shadow: settings.shadowEnabled) else {
            log.error("Photo watermark: renderTextCG failed")
            return jpegData
        }

        var wm = CIImage(cgImage: wmCG)
        let textSize = wm.extent.size

        // Position directly in portrait space (no landscape rotation needed)
        let portraitPad = padding
        let pos = photoPosition(for: settings.corner,
                                 textW: textSize.width,
                                 textH: textSize.height,
                                 imageW: w, imageH: h,
                                 padding: portraitPad)
        wm = wm.transformed(by: CGAffineTransform(translationX: pos.x, y: pos.y))

        guard let filter = CIFilter(name: "CISourceOverCompositing") else {
            log.error("Photo watermark: filter unavailable")
            return jpegData
        }
        filter.setValue(wm, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)

        guard let composited = filter.outputImage?.cropped(to: ext) else {
            log.error("Photo watermark: compositing returned nil")
            return jpegData
        }

        let context = CIContext(options: [.highQualityDownsample: true])
        guard let outputCG = context.createCGImage(composited, from: ext) else {
            log.error("Photo watermark: createCGImage failed")
            return jpegData
        }

        let outputData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outputData, "public.jpeg" as CFString, 1, nil) else {
            log.error("Photo watermark: CGImageDestinationCreate failed")
            return jpegData
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, outputCG, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            log.error("Photo watermark: finalize failed")
            return jpegData
        }

        return outputData as Data
    }

    // MARK: - Photo Positioning

    /// Simple corner positioning in portrait (no rotation needed for photos).
    private static func photoPosition(for corner: WatermarkSettings.Corner,
                                       textW: CGFloat, textH: CGFloat,
                                       imageW: CGFloat, imageH: CGFloat,
                                       padding: CGFloat) -> CGPoint {
        switch corner {
        case .topLeading:     return CGPoint(x: padding, y: imageH - textH - padding)
        case .topTrailing:    return CGPoint(x: imageW - textW - padding, y: imageH - textH - padding)
        case .bottomLeading:  return CGPoint(x: padding, y: padding)
        case .bottomTrailing: return CGPoint(x: imageW - textW - padding, y: padding)
        }
    }

    // MARK: - Text Rendering

    /// Renders a pre-built attributed string (text + inline logo) into a CGImage.
    /// Supports optional drop shadow for readability.
    private static func renderAttributedText(_ attrStr: NSAttributedString,
                                              opacity: Double,
                                              shadow: Bool) -> CGImage? {
        let textSize = attrStr.size()
        let shadowOffset: CGFloat = shadow ? ceil(textSize.height * 0.04) : 0
        let totalSize = CGSize(
            width: textSize.width + padding * 2 + shadowOffset,
            height: textSize.height + padding * 2 + shadowOffset
        )

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false

        return UIGraphicsImageRenderer(size: totalSize, format: fmt).image { ctx in
            let drawOrigin = CGPoint(x: padding, y: padding)

            if shadow {
                let shadowMutable = NSMutableAttributedString(attributedString: attrStr)
                shadowMutable.enumerateAttributes(in: NSRange(location: 0, length: shadowMutable.length)) { attrs, range, _ in
                    var newAttrs = attrs
                    if let color = attrs[.foregroundColor] as? UIColor {
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        color.getRed(&r, green: &g, blue: &b, alpha: &a)
                        newAttrs[.foregroundColor] = UIColor.black.withAlphaComponent(a * 0.5)
                    } else {
                        newAttrs[.foregroundColor] = UIColor.black.withAlphaComponent(0.5)
                    }
                    shadowMutable.setAttributes(newAttrs, range: range)
                }
                shadowMutable.draw(at: CGPoint(x: drawOrigin.x + shadowOffset,
                                               y: drawOrigin.y + shadowOffset))
            }

            // Apply opacity to main text
            let mainMutable = NSMutableAttributedString(attributedString: attrStr)
            mainMutable.enumerateAttributes(in: NSRange(location: 0, length: mainMutable.length)) { attrs, range, _ in
                var newAttrs = attrs
                if let color = attrs[.foregroundColor] as? UIColor {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    newAttrs[.foregroundColor] = UIColor(red: r, green: g, blue: b, alpha: a * CGFloat(opacity))
                } else {
                    newAttrs[.foregroundColor] = UIColor.white.withAlphaComponent(CGFloat(opacity))
                }
                mainMutable.setAttributes(newAttrs, range: range)
            }
            mainMutable.draw(at: drawOrigin)
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
        landscapeExtent: CGRect
    ) -> CGAffineTransform {
        let tw = textSize.width
        let th = textSize.height
        let lw = landscapeExtent.width
        let lh = landscapeExtent.height

        // Step 1: Move center of text to origin
        let toOrigin = CGAffineTransform(translationX: -tw / 2, y: -th / 2)

        // Step 2: Pre-rotate so text reads horizontally after writer rotation.
        let preRotation = CGAffineTransform(rotationAngle: .pi / 2)

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
            landscapeH: lh
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
        landscapeH lh: CGFloat
    ) -> (CGFloat, CGFloat) {
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
