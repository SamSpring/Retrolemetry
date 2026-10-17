import SwiftUI

enum ConsoleStyle: String, CaseIterable {
    case phosphor
    case synthwave

    var palette: ConsolePalette {
        switch self {
        case .phosphor:
            ConsolePalette(
                primary: Color(red: 0.34, green: 1.0, blue: 0.43),
                secondary: Color(red: 0.34, green: 1.0, blue: 0.43).opacity(0.48)
            )
        case .synthwave:
            ConsolePalette(
                primary: Color(red: 0.25, green: 0.96, blue: 1.0),
                secondary: Color(red: 1.0, green: 0.18, blue: 0.72).opacity(0.64)
            )
        }
    }
}

struct ConsolePalette {
    let primary: Color
    let secondary: Color
}

enum ThemeRuntime {
    nonisolated(unsafe) static var palette = ConsoleStyle.phosphor.palette
}

var phosphor: Color { ThemeRuntime.palette.primary }
var dimPhosphor: Color { ThemeRuntime.palette.secondary }

struct ConsoleBackground: View {
    let style: ConsoleStyle
    let phosphorTintStrength: Double

    var body: some View {
        switch style {
        case .phosphor:
            ZStack {
                Color.black
                Color(
                    red: 0.006 * phosphorTintStrength,
                    green: 0.22 * phosphorTintStrength,
                    blue: 0.026 * phosphorTintStrength
                )
                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.55, blue: 0.12).opacity(0.18 * phosphorTintStrength),
                        .clear
                    ],
                    center: .center,
                    startRadius: 30,
                    endRadius: 590
                )
            }
        case .synthwave:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.01, blue: 0.18),
                        Color(red: 0.015, green: 0.01, blue: 0.08),
                        .black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.05, blue: 0.65).opacity(0.18), .clear],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [Color.cyan.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 430
                )
            }
        }
    }
}
