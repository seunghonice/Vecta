import CoreGraphics
import Foundation

/// 씬그래프를 PDF로 그려 .ai 파일 데이터를 만든다.
/// 텍스트·이미지·그라디언트 렌더링은 SceneRenderer 확장에 따라온다.
public enum AIFileWriter {
  public static func data(for document: VectorDocument) throws -> Data {
    let pdf = try renderPDF(document)
    return try NativeScenePayload.embed(document, into: pdf)
  }

  private static func renderPDF(_ document: VectorDocument) throws -> Data {
    let output = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: document.artboard.size)
    guard
      let consumer = CGDataConsumer(data: output as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
      throw ExportError.pdfGenerationFailed
    }
    context.beginPDFPage(nil)
    // 모델 좌표(top-left) → PDF 좌표(bottom-left) 플립
    context.translateBy(x: 0, y: mediaBox.height)
    context.scaleBy(x: 1, y: -1)
    SceneRenderer.render(document, in: context)
    context.endPDFPage()
    context.closePDF()
    return output as Data
  }
}
