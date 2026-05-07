import SwiftUI

struct OutputLogView: View {
    var text: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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
            .padding(.top, 8)
        } label: {
            Label("rclone 输出日志", systemImage: "terminal")
                .font(.headline)
        }
        .panelStyle()
    }
}
