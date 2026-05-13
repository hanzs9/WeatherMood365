import SwiftUI

extension Color {
    static let appAccent = Color(red: 0.17, green: 0.43, blue: 0.61)
    static let brandYellow = Color(red: 1.0, green: 0.82, blue: 0.24)
}

extension UIColor {
    static let appAccent = UIColor(red: 0.17, green: 0.43, blue: 0.61, alpha: 1)
    static let brandYellow = UIColor(red: 1.0, green: 0.82, blue: 0.24, alpha: 1)
}

enum AppRadius {
    static let small: CGFloat = 8
    static let standard: CGFloat = 12
    static let primary: CGFloat = 16
    static let overlay: CGFloat = 24
}

struct PressableButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var pressedScale: CGFloat = 0.98
    var overlayColor: Color = .black.opacity(0.08)
    var shadowColor: Color = .black.opacity(0)
    var shadowRadius: CGFloat = 0
    var shadowY: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            .overlay {
                shape
                    .fill(overlayColor)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .shadow(
                color: shadowColor.opacity(configuration.isPressed ? 1 : 0),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle<RoundedRectangle> {
    static func pressableCard(
        cornerRadius: CGFloat = 16,
        pressedScale: CGFloat = 0.98,
        overlayColor: Color = .black.opacity(0.06),
        shadowColor: Color = .black.opacity(0),
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> PressableButtonStyle<RoundedRectangle> {
        PressableButtonStyle(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            pressedScale: pressedScale,
            overlayColor: overlayColor,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }
}
