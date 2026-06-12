import SwiftUI
import VectaEngine

/// 임포트 경고 비모달 배너 (스펙 §5) — "N개 객체를 가져오지 못했습니다 (자세히)".
struct ImportReportBanner: View {
  let report: ImportReport
  let onDismiss: () -> Void
  @State private var showingDetails = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      Text("\(report.issues.count)개 객체를 가져오지 못했습니다")
      Button("자세히") {
        showingDetails = true
      }
      .buttonStyle(.link)
      .popover(isPresented: $showingDetails) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
            Text("• \(issue.detail)")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(12)
        .frame(maxWidth: 360)
      }
      Spacer()
      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help("배너 닫기")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.yellow.opacity(0.15))
  }
}
