import Foundation

public enum AIFileReader {
  /// M1: Voida가 저장한 파일(임베드 JSON)만 연다.
  /// M4에서 noNativeData 경로가 콘텐츠 스트림 파싱 폴백으로 대체된다.
  public static func document(from data: Data) throws -> VectorDocument {
    guard data.starts(with: Data("%PDF-".utf8)) else {
      throw ImportError.notPDF
    }
    guard let native = try NativeScenePayload.extract(from: data) else {
      throw ImportError.noNativeData
    }
    return native
  }
}
