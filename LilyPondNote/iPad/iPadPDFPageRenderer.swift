// iPadのページ送り表示に使うPDFページ画像を生成する。

import CoreGraphics
import Foundation
import PDFKit

struct RenderedPDFPage: Identifiable {
    struct ID: Hashable {
        let documentFingerprint: Int
        let pageIndex: Int
    }

    let index: Int
    let data: Data
    let documentFingerprint: Int

    var id: ID {
        ID(documentFingerprint: documentFingerprint, pageIndex: index)
    }
}

enum PDFPageRenderer {
    private static let pixelHeight = 1800

    /// PDFの各ページを識別可能な表示用データへ分解する。
    static func render(data: Data) -> [RenderedPDFPage] {
        guard let document = PDFDocument(data: data) else { return [] }
        let documentFingerprint = data.hashValue

        return (0..<document.pageCount).map { index in
            RenderedPDFPage(
                index: index,
                data: data,
                documentFingerprint: documentFingerprint
            )
        }
    }

    /// 指定ページをCGImageとして描画する。
    static func renderPage(data: Data, index: Int) -> CGImage? {
        guard let document = PDFDocument(data: data),
              let pdfPage = document.page(at: index)?.pageRef else { return nil }
        return render(pdfPage: pdfPage)
    }

    /// PDFの各ページを識別可能な表示用データへ分解する。
    private static func render(pdfPage: CGPDFPage) -> CGImage? {
        let bounds = pdfPage.getBoxRect(.cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let pixelWidth = max(
            1,
            Int(CGFloat(pixelHeight) * bounds.width / bounds.height)
        )
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(
            x: CGFloat(pixelWidth) / bounds.width,
            y: CGFloat(pixelHeight) / bounds.height
        )
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(pdfPage)
        return context.makeImage()
    }
}
