import InputEngine
import SwiftUI

/// Top-down outline of the Pro Click Mini with a clickable hotspot per button.
struct MouseDiagram: View {
    @Binding var selection: ButtonID?

    var body: some View {
        ZStack {
            MouseOutline()
                .fill(.quaternary)
                .overlay(MouseOutline().stroke(.secondary, lineWidth: 1.5))
            Path { p in  // split between left and right buttons
                p.move(to: CGPoint(x: 80, y: 8)); p.addLine(to: CGPoint(x: 80, y: 110))
            }
            .stroke(.secondary, lineWidth: 1)
            hotspot(.left, CGRect(x: 18, y: 18, width: 56, height: 80))
            hotspot(.right, CGRect(x: 86, y: 18, width: 56, height: 80))
            hotspot(.tiltLeft, CGRect(x: 60, y: 34, width: 14, height: 36), systemImage: "chevron.left")
            hotspot(.wheel, CGRect(x: 74, y: 30, width: 12, height: 44))
            hotspot(.tiltRight, CGRect(x: 86, y: 34, width: 14, height: 36), systemImage: "chevron.right")
            hotspot(.button5, CGRect(x: 0, y: 112, width: 14, height: 30))
            hotspot(.button4, CGRect(x: 0, y: 146, width: 14, height: 30))
        }
        .frame(width: 160, height: 250)
    }

    private func hotspot(_ id: ButtonID, _ r: CGRect, systemImage: String? = nil) -> some View {
        let selected = selection == id
        return Button {
            selection = id
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.accentColor.opacity(0.45) : Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: selected ? 2 : 0.5))
                .overlay { if let systemImage { Image(systemName: systemImage).font(.caption2) } }
                .frame(width: r.width, height: r.height)
        }
        .buttonStyle(.plain)
        .help(id.title)
        .position(x: r.midX, y: r.midY)
    }
}

/// A rounded, slightly egg-shaped mouse body, wider at the back.
struct MouseOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 4))
        p.addCurve(to: CGPoint(x: w - 6, y: h * 0.45), control1: CGPoint(x: w * 0.88, y: 4),
                   control2: CGPoint(x: w - 6, y: h * 0.2))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h - 4), control1: CGPoint(x: w - 6, y: h * 0.8),
                   control2: CGPoint(x: w * 0.85, y: h - 4))
        p.addCurve(to: CGPoint(x: 6, y: h * 0.45), control1: CGPoint(x: w * 0.15, y: h - 4),
                   control2: CGPoint(x: 6, y: h * 0.8))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 4), control1: CGPoint(x: 6, y: h * 0.2),
                   control2: CGPoint(x: w * 0.12, y: 4))
        return p
    }
}
