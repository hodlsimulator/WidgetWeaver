//
//  SmartPhotoCropRotationPreview.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import UIKit

enum SmartPhotoCropRotationPreview {
    static func normalisedQuarterTurns(_ quarterTurns: Int) -> Int {
        let t = quarterTurns % 4
        return (t + 4) % 4
    }

    static func rotatedPreviewImage(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let t = normalisedQuarterTurns(quarterTurns)
        guard t != 0 else { return image }

        let source = normalisedOrientation(image)
        let sourceSize = source.size
        let newSize: CGSize = (t % 2 == 0) ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)

        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2.0, y: newSize.height / 2.0)
            c.rotate(by: CGFloat(t) * (.pi / 2.0))
            source.draw(
                in: CGRect(
                    x: -sourceSize.width / 2.0,
                    y: -sourceSize.height / 2.0,
                    width: sourceSize.width,
                    height: sourceSize.height
                )
            )
        }
    }

    private static func normalisedOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
