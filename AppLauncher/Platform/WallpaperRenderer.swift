import CoreImage
import ImageIO

enum WallpaperRenderer {
    nonisolated private static let maximumDimension = 2_048
    nonisolated private static let blurRadius: CGFloat = 24

    @concurrent
    static func render(_ source: WallpaperSource) async throws -> CGImage {
        try Task.checkCancellation()
        let target = targetPixelSize(for: source)
        guard
            let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil),
            let decoded = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        else {
            throw WallpaperRenderError.cannotDecode
        }

        try Task.checkCancellation()
        let sourceImage = CIImage(cgImage: decoded)
        let targetRect = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        let transform = placementTransform(
            sourceSize: sourceImage.extent.size,
            targetSize: targetRect.size,
            scaling: source.scaling,
            allowsClipping: source.allowsClipping
        )
        let placed = sourceImage.transformed(by: transform)
        let background = CIImage(
            color: CIColor(
                red: source.fillColor.red,
                green: source.fillColor.green,
                blue: source.fillColor.blue,
                alpha: source.fillColor.alpha
            )
        ).cropped(to: targetRect)
        let composed = placed.composited(over: background).cropped(to: targetRect)
        let blurred =
            composed
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(blurRadius * source.backingScale))
            .cropped(to: targetRect)

        try Task.checkCancellation()
        if let result = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(blurred, from: targetRect)
        {
            return result
        }
        try Task.checkCancellation()
        let softwareContext = CIContext(options: [
            .cacheIntermediates: false,
            .useSoftwareRenderer: true,
        ])
        guard let result = softwareContext.createCGImage(blurred, from: targetRect) else {
            throw WallpaperRenderError.cannotRender
        }
        return result
    }

    nonisolated static func targetPixelSize(
        for source: WallpaperSource
    ) -> (width: Int, height: Int) {
        let desiredWidth = max(1, source.pointWidth * source.backingScale)
        let desiredHeight = max(1, source.pointHeight * source.backingScale)
        let reduction = min(1, CGFloat(maximumDimension) / max(desiredWidth, desiredHeight))
        return (
            max(1, Int((desiredWidth * reduction).rounded(.up))),
            max(1, Int((desiredHeight * reduction).rounded(.up)))
        )
    }

    nonisolated static func placementTransform(
        sourceSize: CGSize,
        targetSize: CGSize,
        scaling: WallpaperScaling,
        allowsClipping: Bool
    ) -> CGAffineTransform {
        let widthScale = targetSize.width / sourceSize.width
        let heightScale = targetSize.height / sourceSize.height
        let scaleX: CGFloat
        let scaleY: CGFloat

        switch scaling {
        case .axesIndependently:
            scaleX = widthScale
            scaleY = heightScale
        case .proportionallyDown:
            let scale = min(
                1, allowsClipping ? max(widthScale, heightScale) : min(widthScale, heightScale))
            scaleX = scale
            scaleY = scale
        case .proportionallyUpOrDown:
            let scale = allowsClipping ? max(widthScale, heightScale) : min(widthScale, heightScale)
            scaleX = scale
            scaleY = scale
        case .none:
            scaleX = 1
            scaleY = 1
        }

        let scaledWidth = sourceSize.width * scaleX
        let scaledHeight = sourceSize.height * scaleY
        let translationX = (targetSize.width - scaledWidth) / 2
        let translationY = (targetSize.height - scaledHeight) / 2
        return CGAffineTransform(translationX: translationX, y: translationY)
            .scaledBy(x: scaleX, y: scaleY)
    }
}

private enum WallpaperRenderError: Error {
    case cannotDecode
    case cannotRender
}
