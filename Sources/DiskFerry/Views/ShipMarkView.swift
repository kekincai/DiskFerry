import SwiftUI

struct ShipMarkView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)

            Canvas { context, size in
                let width = size.width
                let height = size.height
                let hullTop = height * 0.56
                let hullBottom = height * 0.72

                var cabin = Path()
                cabin.move(to: CGPoint(x: width * 0.34, y: height * 0.28))
                cabin.addLine(to: CGPoint(x: width * 0.66, y: height * 0.28))
                cabin.addLine(to: CGPoint(x: width * 0.72, y: hullTop))
                cabin.addLine(to: CGPoint(x: width * 0.27, y: hullTop))
                cabin.closeSubpath()
                context.fill(cabin, with: .color(.accentColor.opacity(0.72)))

                for index in 0..<3 {
                    let x = width * (0.39 + Double(index) * 0.11)
                    let rect = CGRect(x: x, y: height * 0.38, width: width * 0.055, height: height * 0.075)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.92)))
                }

                var hull = Path()
                hull.move(to: CGPoint(x: width * 0.18, y: hullTop))
                hull.addLine(to: CGPoint(x: width * 0.83, y: hullTop))
                hull.addLine(to: CGPoint(x: width * 0.72, y: hullBottom))
                hull.addLine(to: CGPoint(x: width * 0.29, y: hullBottom))
                hull.closeSubpath()
                context.fill(hull, with: .color(.primary.opacity(0.82)))

                for offset in [0.0, 0.12] {
                    var wave = Path()
                    let y = height * (0.80 + offset)
                    wave.move(to: CGPoint(x: width * 0.18, y: y))
                    wave.addCurve(
                        to: CGPoint(x: width * 0.46, y: y),
                        control1: CGPoint(x: width * 0.27, y: y - height * 0.06),
                        control2: CGPoint(x: width * 0.37, y: y + height * 0.06)
                    )
                    wave.addCurve(
                        to: CGPoint(x: width * 0.74, y: y),
                        control1: CGPoint(x: width * 0.55, y: y - height * 0.06),
                        control2: CGPoint(x: width * 0.65, y: y + height * 0.06)
                    )
                    context.stroke(wave, with: .color(.accentColor), lineWidth: 2.2)
                }
            }
            .padding(4)
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel("Disk Ferry")
    }
}
