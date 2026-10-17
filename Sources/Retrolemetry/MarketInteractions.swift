import Foundation

/// Kept identical to the ticker's explicit header, padding and row spacing.
enum MarketTickerGeometry {
    static func headerHeight(_ typography: ConsoleTypography) -> Double { max(12, 11 * typography.scale(.secondary, dimmed: true)) }
    static func row(at point: CGPoint, frame: ModuleFrame, typography: ConsoleTypography) -> Int? {
        guard frame.visible, frame.rect.contains(point) else { return nil }
        let header = headerHeight(typography)
        let top = frame.y + 7 + header + 1 + 6
        let height = max(0, (frame.height - 14 - header - 1 - 18) / 5)
        guard height > 0, point.y >= top else { return nil }
        let row = Int((point.y - top) / (height + 3))
        return (0..<5).contains(row) && point.y <= top + Double(row) * (height + 3) + height ? row : nil
    }
}
