import SwiftUI

struct OutputLogView: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("rclone 输出日志")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "rclone 的 stdout / stderr 会显示在这里。" : text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                        .padding(12)
                }
                .frame(minHeight: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .panelStyle()
    }
}
