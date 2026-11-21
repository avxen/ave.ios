// CrosshairOverlay.swift
// Private Judges Workspace - crosshair placement and adjustment overlay.
//
// Placement, adjustment and display route ONLY through CoordinateEngine;
// the drag gesture converts view locations to canonical PixelPoints via
// normalized coordinates - never raw view points.

import SwiftUI

struct CrosshairOverlay: View {
    let imageDisplaySize: CGSize
    let imagePixelSize: CGSize
    @Binding var point: CoordinateEngine.PixelPoint
    var consensusPoint: CoordinateEngine.PixelPoint?
    var otherJudges: [CoordinateEngine.PixelPoint] = []
    var interactive = true

    @State private var dragStart: CoordinateEngine.PixelPoint?
    @State private var fineAdjust = false

    private func pixel(from location: CGPoint) -> CoordinateEngine.PixelPoint {
        guard imageDisplaySize.width > 0, imageDisplaySize.height > 0,
              imagePixelSize.width >= 2, imagePixelSize.height >= 2 else {
            return CoordinateEngine.PixelPoint(x: 0, y: 0)
        }
        let nx = Double(location.x / imageDisplaySize.width)
        let ny = Double(location.y / imageDisplaySize.height)
        return (try? CoordinateEngine.fromNormalized(
            nx, ny, width: Int(imagePixelSize.width),
            height: Int(imagePixelSize.height))) ?? CoordinateEngine.PixelPoint(x: 0, y: 0)
    }

    private func displayOffset(_ p: CoordinateEngine.PixelPoint) -> CGPoint {
        guard imagePixelSize.width >= 1, imagePixelSize.height >= 1,
              imageDisplaySize.width > 0, imageDisplaySize.height > 0 else { return .zero }
        return CGPoint(
            x: (Double(p.x) / Double(Int(imagePixelSize.width))) * imageDisplaySize.width,
            y: (Double(p.y) / Double(Int(imagePixelSize.height))) * imageDisplaySize.height)
    }

    var body: some View {
        ZStack {
            // Other judges' markers (faint)
            ForEach(Array(otherJudges.enumerated()), id: \.offset) { _, p in
                let o = displayOffset(p)
                Circle()
                    .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .position(o)
            }
            // Consensus marker
            if let c = consensusPoint {
                let o = displayOffset(c)
                Image(systemName: "scope")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.green)
                    .position(o)
            }
            // Authoritative judge crosshair
            let o = displayOffset(point)
            CrosshairShape()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: 40, height: 40)
                .position(o)
            Text("\(point.x), \(point.y) px")
                .font(.caption.monospaced())
                .padding(4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .position(x: o.x, y: max(24, o.y - 34))
        }
        .contentShape(Rectangle())
        .gesture(interactive ? placementGesture : nil)
    }

    private var placementGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = point }
                if fineAdjust, let start = dragStart {
                    // fine mode: move at most 1 px per 4 display points
                    let dx = Double(value.location.x - value.startLocation.x)
                    let dy = Double(value.location.y - value.startLocation.y)
                    let maxX = Int(imagePixelSize.width) - 1
                    let maxY = Int(imagePixelSize.height) - 1
                    point = CoordinateEngine.PixelPoint(
                        x: (start.x + Int(dx / 4)).clamped(0...max(1, maxX)),
                        y: (start.y + Int(dy / 4)).clamped(0...max(1, maxY)))
                } else {
                    point = pixel(from: value.location)
                }
            }
            .onEnded { _ in dragStart = nil }
    }
}

struct CrosshairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: CGPoint(x: rect.minX, y: c.y)); p.addLine(to: CGPoint(x: rect.maxX, y: c.y))
        p.move(to: CGPoint(x: c.x, y: rect.minY)); p.addLine(to: CGPoint(x: c.x, y: rect.maxY))
        p.addEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
        return p
    }
}
