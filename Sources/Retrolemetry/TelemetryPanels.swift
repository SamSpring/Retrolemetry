import SwiftUI

struct CapacitySummary: View {
    let capacity: CapacityReading?
    let fit: Double

    var body: some View {
        HStack(spacing: 8 * fit) {
            amount("USED", bytes: capacity?.usedBytes)
            Spacer(minLength: 0)
            amount("FREE", bytes: capacity?.freeBytes)
        }
        .lineLimit(1).minimumScaleFactor(0.35)
    }

    private func amount(_ title: String, bytes: Double?) -> some View {
        HStack(spacing: 4 * fit) {
            Text(title).consoleFont(9 * fit, role: .dark, weight: .bold).consoleDimmed()
            Text(capacityAmount(bytes)).consoleFont(11 * fit, role: .primary, weight: .bold)
        }
    }
}

/// Shared header keeps every graph's trace below its title and current reading.
struct DataGraphHeader: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    private var title: some View {
        Text(label).consoleFont(13, role: .secondary, weight: .bold)
            .lineLimit(1).minimumScaleFactor(0.25)
    }
    private var reading: some View {
        Text(value).consoleFont(18, role: .primary, weight: .bold)
            .foregroundStyle(valueColor ?? phosphor)
            .lineLimit(1).minimumScaleFactor(0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title.fixedSize()
                    Spacer(minLength: 4)
                    reading.fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    reading
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(dimPhosphor.opacity(0.72)).frame(height: 1)
        }
    }
}

/// Same bytes/second scale on both sides; no fixed-speed ceiling or RX/TX summing.
enum NetworkHistoryGeometry {
    static func scale(receive: [Double], transmit: [Double]) -> Double {
        max(1_000, (receive + transmit).filter { $0.isFinite && $0 >= 0 }.max() ?? 0)
    }

    static func segments(_ rates: [Double], in rect: CGRect, scale: Double, transmit: Bool) -> [[CGPoint]] {
        guard rect.width > 0, rect.height > 0, scale.isFinite, scale > 0 else { return [] }
        let values = rates.map { rate -> Double? in
            rate.isFinite && rate >= 0 ? min(1, rate / scale) : nil
        }
        let segments = UsageHistoryGeometry.segments(values, in: rect)
        return transmit ? segments : segments.map { $0.map { CGPoint(x: $0.x, y: rect.maxY + rect.minY - $0.y) } }
    }
}

struct NetworkTrafficPanel: View {
    let transmit: Double
    let receiveHistory: [Double]
    let transmitHistory: [Double]
    @AppStorage("DockTelemetry.visualStyle") private var styleRaw = ConsoleStyle.phosphor.rawValue
    @Environment(\.consoleTypography) private var typography

    private var transmitColor: Color {
        styleRaw == ConsoleStyle.synthwave.rawValue
            ? Color(red: 1, green: 0.18, blue: 0.72) : phosphor
    }

    var body: some View {
        VStack(spacing: 0) {
            DataGraphHeader(label: "NETWORK TX // 96 SEC", value: byteRate(transmit), valueColor: transmitColor)
            Canvas { context, size in
                guard size.width > 0, size.height > 4 else { return }
                let mid = size.height / 2
                let inset = min(6, size.height / 8)
                let top = CGRect(x: 0, y: inset, width: size.width, height: mid - inset)
                let bottom = CGRect(x: 0, y: mid, width: size.width, height: mid - inset)
                let scale = NetworkHistoryGeometry.scale(receive: receiveHistory, transmit: transmitHistory)
                drawGrid(context: &context, size: size, columns: 12, rows: 4)
                var center = Path()
                center.move(to: CGPoint(x: 0, y: mid))
                center.addLine(to: CGPoint(x: size.width, y: mid))
                context.stroke(center, with: .color(phosphor.opacity(0.55)), lineWidth: 1)
                draw(transmitHistory, in: top, scale: scale, transmit: true, color: transmitColor, context: &context)
                draw(receiveHistory, in: bottom, scale: scale, transmit: false, color: phosphor, context: &context)
                // Fixed-position legends are inside the clipped plot, never over its header.
                if size.height >= 44 {
                    let fontSize = min(9 * typography.secondary, size.height / 7)
                    context.draw(Text("TX ↑").font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(transmitColor), at: CGPoint(x: 5, y: 3), anchor: .topLeading)
                    context.draw(Text("RX ↓").font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(phosphor), at: CGPoint(x: 5, y: size.height - 3), anchor: .bottomLeading)
                }
            }
            .clipped()
        }
        .overlay(Rectangle().stroke(dimPhosphor, lineWidth: 1))
        .clipped()
        .help("Last 96 samples, about 96 seconds. TX uploads rise above the center; RX downloads extend below it. Both use the same automatically scaled bytes/second range.")
    }

    private func draw(_ values: [Double], in rect: CGRect, scale: Double, transmit: Bool,
                      color: Color, context: inout GraphicsContext) {
        let baseline = transmit ? rect.maxY : rect.minY
        for points in NetworkHistoryGeometry.segments(values, in: rect, scale: scale, transmit: transmit) {
            guard let first = points.first, let last = points.last else { continue }
            var line = Path()
            line.move(to: first)
            for point in points.dropFirst() { line.addLine(to: point) }
            var fill = line
            fill.addLine(to: CGPoint(x: last.x, y: baseline))
            fill.addLine(to: CGPoint(x: first.x, y: baseline))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.16)))
            if points.count == 1 {
                context.fill(Path(ellipseIn: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)), with: .color(color))
            } else {
                context.stroke(line, with: .color(color), lineWidth: 1.6)
            }
        }
    }
}
