import SwiftUI

struct WaveProgressView: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, fraction))
            let shipX = max(18, min(proxy.size.width - 18, proxy.size.width * clamped))

            ZStack(alignment: .leading) {
                WaveLine(amplitude: 4, progress: 1)
                    .stroke(.secondary.opacity(0.24), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                WaveLine(amplitude: 4, progress: clamped)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                MiniShip()
                    .frame(width: 34, height: 24)
                    .offset(x: shipX - 17, y: -10)
            }
        }
        .frame(height: 32)
        .accessibilityLabel("复制进度")
    }
}

private struct WaveLine: Shape {
    var amplitude: CGFloat
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let endX = rect.width * max(0, min(1, progress))
        let midY = rect.midY + 8
        var x: CGFloat = 0
        path.move(to: CGPoint(x: 0, y: midY))
        while x <= endX {
            let y = midY + sin(x / 12) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        return path
    }
}

private struct MiniShip: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            var hull = Path()
            hull.move(to: CGPoint(x: w * 0.08, y: h * 0.55))
            hull.addLine(to: CGPoint(x: w * 0.92, y: h * 0.55))
            hull.addLine(to: CGPoint(x: w * 0.74, y: h * 0.82))
            hull.addLine(to: CGPoint(x: w * 0.26, y: h * 0.82))
            hull.closeSubpath()
            context.fill(hull, with: .color(.primary))

            var cabin = Path()
            cabin.move(to: CGPoint(x: w * 0.34, y: h * 0.25))
            cabin.addLine(to: CGPoint(x: w * 0.66, y: h * 0.25))
            cabin.addLine(to: CGPoint(x: w * 0.72, y: h * 0.55))
            cabin.addLine(to: CGPoint(x: w * 0.28, y: h * 0.55))
            cabin.closeSubpath()
            context.fill(cabin, with: .color(.accentColor))
        }
    }
}
