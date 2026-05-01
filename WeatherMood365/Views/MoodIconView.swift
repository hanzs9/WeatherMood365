import SwiftUI

struct MoodIconView: View {
    let mood: Mood
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)

            face
                .stroke(lineColor, style: StrokeStyle(lineWidth: max(size * 0.07, 1.25), lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        switch mood {
        case .happy: .yellow.opacity(0.92)
        case .plain: .gray.opacity(0.22)
        case .cozy: .green.opacity(0.24)
        case .irritated: .orange.opacity(0.24)
        case .low: .indigo.opacity(0.18)
        }
    }

    private var lineColor: Color {
        switch mood {
        case .happy: .orange
        case .plain: .gray
        case .cozy: .green
        case .irritated: .red
        case .low: .indigo
        }
    }

    private var face: Path {
        Path { path in
            switch mood {
            case .happy:
                dotEyes(in: &path, y: 0.38)
                path.move(to: CGPoint(x: size * 0.32, y: size * 0.56))
                path.addQuadCurve(to: CGPoint(x: size * 0.68, y: size * 0.56), control: CGPoint(x: size * 0.5, y: size * 0.74))
            case .plain:
                dotEyes(in: &path, y: 0.39)
                path.move(to: CGPoint(x: size * 0.34, y: size * 0.61))
                path.addLine(to: CGPoint(x: size * 0.66, y: size * 0.61))
            case .cozy:
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.39))
                path.addQuadCurve(to: CGPoint(x: size * 0.43, y: size * 0.39), control: CGPoint(x: size * 0.365, y: size * 0.34))
                path.move(to: CGPoint(x: size * 0.57, y: size * 0.39))
                path.addQuadCurve(to: CGPoint(x: size * 0.7, y: size * 0.39), control: CGPoint(x: size * 0.635, y: size * 0.34))
                path.move(to: CGPoint(x: size * 0.34, y: size * 0.58))
                path.addQuadCurve(to: CGPoint(x: size * 0.66, y: size * 0.58), control: CGPoint(x: size * 0.5, y: size * 0.7))
            case .irritated:
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.31))
                path.addLine(to: CGPoint(x: size * 0.43, y: size * 0.36))
                path.move(to: CGPoint(x: size * 0.7, y: size * 0.31))
                path.addLine(to: CGPoint(x: size * 0.57, y: size * 0.36))
                dotEyes(in: &path, y: 0.43)
                path.move(to: CGPoint(x: size * 0.34, y: size * 0.66))
                path.addQuadCurve(to: CGPoint(x: size * 0.66, y: size * 0.66), control: CGPoint(x: size * 0.5, y: size * 0.52))
            case .low:
                path.move(to: CGPoint(x: size * 0.3, y: size * 0.43))
                path.addQuadCurve(to: CGPoint(x: size * 0.43, y: size * 0.45), control: CGPoint(x: size * 0.36, y: size * 0.49))
                path.move(to: CGPoint(x: size * 0.57, y: size * 0.45))
                path.addQuadCurve(to: CGPoint(x: size * 0.7, y: size * 0.43), control: CGPoint(x: size * 0.64, y: size * 0.49))
                path.move(to: CGPoint(x: size * 0.34, y: size * 0.67))
                path.addQuadCurve(to: CGPoint(x: size * 0.66, y: size * 0.67), control: CGPoint(x: size * 0.5, y: size * 0.52))
            }
        }
    }

    private func dotEyes(in path: inout Path, y: CGFloat) {
        let leftEye = CGPoint(x: size * 0.36, y: size * y)
        let rightEye = CGPoint(x: size * 0.64, y: size * y)
        path.move(to: leftEye)
        path.addLine(to: leftEye)
        path.move(to: rightEye)
        path.addLine(to: rightEye)
    }
}

struct MoodTextView: View {
    let mood: Mood
    var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 5) {
            MoodIconView(mood: mood, size: iconSize)
            Text(mood.title)
        }
    }
}
