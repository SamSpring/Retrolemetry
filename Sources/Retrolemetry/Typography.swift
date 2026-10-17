import SwiftUI

enum ConsoleFontRole: String, CaseIterable {
    case primary, dark, secondary, other, frameHeader, frameFooter
    static let allCases: [Self] = [.primary, .dark, .secondary, .frameHeader, .frameFooter]
    var title: String {
        switch self {
        case .primary: "Metrics / stats"
        case .dark: "Dark texts"
        case .secondary: "Main text"
        case .other: "Module text"
        case .frameHeader: "Frame header"
        case .frameFooter: "Frame footer"
        }
    }
}

struct ConsoleTypography: Codable, Equatable {
    private var legacyPrimary: Double
    private var legacySecondary: Double
    private var legacyOther: Double
    var groups: [String: Double] = [:]

    init(primary: Double = 1, secondary: Double = 1, other: Double = 1, groups: [String: Double] = [:]) {
        legacyPrimary = primary; legacySecondary = secondary; legacyOther = other; self.groups = groups
    }
    var primary: Double { self[.primary] }
    var secondary: Double { self[.secondary] }
    var other: Double { self[.other] }

    private func inherited(_ role: ConsoleFontRole) -> Double {
        switch role {
        case .primary: legacyPrimary
        case .dark, .secondary: legacySecondary
        case .other, .frameHeader, .frameFooter: legacyOther
        }
    }
    static func resolvedRole(_ role: ConsoleFontRole, dimmed: Bool) -> ConsoleFontRole {
        dimmed ? .dark : role
    }
    func scale(_ role: ConsoleFontRole, fallback: ConsoleFontRole? = nil, dimmed: Bool = false) -> Double {
        groups[Self.resolvedRole(role, dimmed: dimmed).rawValue] ?? inherited(fallback ?? role)
    }

    subscript(_ role: ConsoleFontRole) -> Double {
        get { scale(role) }
        set { groups[role.rawValue] = newValue }
    }
    func font(_ size: Double, role: ConsoleFontRole, weight: Font.Weight = .regular, fallback: ConsoleFontRole? = nil, dimmed: Bool = false) -> Font {
        .system(size: size * scale(role, fallback: fallback, dimmed: dimmed), weight: weight, design: .monospaced)
    }

    // Decode old three-slider exports without migrating preferences or altering their appearance.
    private enum CodingKeys: String, CodingKey { case primary, secondary, other, groups }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        legacyPrimary = try c.decode(Double.self, forKey: .primary)
        legacySecondary = try c.decode(Double.self, forKey: .secondary)
        legacyOther = try c.decode(Double.self, forKey: .other)
        groups = try c.decodeIfPresent([String: Double].self, forKey: .groups) ?? [:]
        groups = groups.filter { $0.value.isFinite && (0.65...3).contains($0.value) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(legacyPrimary, forKey: .primary)
        try c.encode(legacySecondary, forKey: .secondary)
        try c.encode(legacyOther, forKey: .other)
        if !groups.isEmpty { try c.encode(groups, forKey: .groups) }
    }
}

private struct ConsoleTypographyKey: EnvironmentKey {
    static let defaultValue = ConsoleTypography()
}
private struct ConsoleDimTextKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var consoleTypography: ConsoleTypography {
        get { self[ConsoleTypographyKey.self] }
        set { self[ConsoleTypographyKey.self] = newValue }
    }
    var consoleDimText: Bool {
        get { self[ConsoleDimTextKey.self] }
        set { self[ConsoleDimTextKey.self] = newValue }
    }
}
private struct ConsoleFontModifier: ViewModifier {
    @Environment(\.consoleTypography) private var typography
    @Environment(\.consoleDimText) private var dimmed
    let size: Double
    let role: ConsoleFontRole
    let weight: Font.Weight
    let fallback: ConsoleFontRole?
    func body(content: Content) -> some View { content.font(typography.font(size, role: role, weight: weight, fallback: fallback, dimmed: dimmed)) }
}
/// Pair the muted palette with its typography group. Dim appearance takes precedence
/// over a label's semantic role, including when inherited by a whole row/container.
private struct ConsoleDimTextModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.foregroundStyle(enabled ? dimPhosphor : phosphor)
            .environment(\.consoleDimText, enabled)
    }
}
extension View {
    func consoleFont(_ size: Double, role: ConsoleFontRole, weight: Font.Weight = .regular, fallback: ConsoleFontRole? = nil) -> some View {
        modifier(ConsoleFontModifier(size: size, role: role, weight: weight, fallback: fallback))
    }
    func consoleDimmed(_ enabled: Bool = true) -> some View {
        modifier(ConsoleDimTextModifier(enabled: enabled))
    }
}
