import CoreImage.CIFilterBuiltins
import UIKit

enum QRShareCardRenderer {
    private static let context = CIContext()

    static func makeCard(product: OfferProduct, code: CodeEntry, appIcon: UIImage?) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { renderContext in
            let bounds = CGRect(origin: .zero, size: size)
            let background = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
                    : UIColor(red: 0.94, green: 0.95, blue: 0.93, alpha: 1)
            }
            background.setFill()
            renderContext.fill(bounds)

            let cardRect = bounds.insetBy(dx: 78, dy: 92)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 72)
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
                    : UIColor.white
            }.setFill()
            cardPath.fill()

            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(white: 1, alpha: 0.08)
                    : UIColor(white: 0, alpha: 0.08)
            }.setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            drawHeader(product: product, appIcon: appIcon, in: cardRect)

            if let qrCode = makeQRCode(from: code.redeemURL.absoluteString, sideLength: 620) {
                let qrRect = CGRect(
                    x: cardRect.midX - 310,
                    y: cardRect.minY + 360,
                    width: 620,
                    height: 620
                )
                let qrBackground = UIBezierPath(roundedRect: qrRect.insetBy(dx: -28, dy: -28), cornerRadius: 42)
                UIColor.white.setFill()
                qrBackground.fill()
                qrCode.draw(in: qrRect)

                if let appIcon {
                    drawEmbeddedIcon(appIcon, in: qrRect)
                }
            }

            drawFooter(product: product, in: cardRect)
        }
    }

    private static func drawHeader(product: OfferProduct, appIcon: UIImage?, in cardRect: CGRect) {
        let iconRect = CGRect(x: cardRect.minX + 72, y: cardRect.minY + 76, width: 112, height: 112)
        if let appIcon {
            UIGraphicsGetCurrentContext()?.saveGState()
            UIBezierPath(roundedRect: iconRect, cornerRadius: 25).addClip()
            appIcon.draw(in: iconRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }

        let titleRect = CGRect(x: iconRect.maxX + 30, y: iconRect.minY + 6, width: cardRect.width - 286, height: 104)
        drawText(
            product.appName,
            in: titleRect,
            font: .systemFont(ofSize: 48, weight: .bold),
            color: .label
        )

        drawText(
            product.displayProductName,
            in: titleRect.offsetBy(dx: 0, dy: 58),
            font: .systemFont(ofSize: 34, weight: .regular),
            color: .secondaryLabel
        )
    }

    private static func drawFooter(product: OfferProduct, in cardRect: CGRect) {
        let titleRect = CGRect(x: cardRect.minX + 72, y: cardRect.maxY - 226, width: cardRect.width - 144, height: 58)
        drawText(
            "Offer Code",
            in: titleRect,
            font: .systemFont(ofSize: 42, weight: .bold),
            color: .label,
            alignment: .center
        )

        let instructionRect = titleRect.offsetBy(dx: 0, dy: 68)
        drawText(
            "Scan to redeem \(product.appName) in the App Store.",
            in: instructionRect,
            font: .systemFont(ofSize: 30, weight: .regular),
            color: .secondaryLabel,
            alignment: .center
        )
    }

    private static func makeQRCode(from string: String, sideLength: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = sideLength / outputImage.extent.width
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func drawEmbeddedIcon(_ appIcon: UIImage, in qrRect: CGRect) {
        let backingSize: CGFloat = 168
        let iconSize: CGFloat = 132
        let backingRect = CGRect(
            x: qrRect.midX - backingSize / 2,
            y: qrRect.midY - backingSize / 2,
            width: backingSize,
            height: backingSize
        )
        let iconRect = CGRect(
            x: qrRect.midX - iconSize / 2,
            y: qrRect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )

        UIColor.white.setFill()
        UIBezierPath(roundedRect: backingRect, cornerRadius: 38).fill()

        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: iconRect, cornerRadius: 30).addClip()
        appIcon.draw(in: iconRect)
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail

        text.draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
