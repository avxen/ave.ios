// ImageViewerView.swift
// Private Judges Workspace - high-resolution viewer with zoom, pan and
// native-resolution crosshair placement.
//
// The crosshair math is invariant to zoom: the overlay lives inside the
// aspect-fit image frame, so gestures report locations in unscaled image
// space and every conversion still runs through CoordinateEngine.

import SwiftUI
import CoreGraphics

struct ImageViewerView: View {
    let imageData: Data
    let widthPx: Int
    let heightPx: Int
    var consensusPoint: CoordinateEngine.PixelPoint?
    var otherJudges: [CoordinateEngine.PixelPoint] = []
    var onSave: ((CoordinateEngine.PixelPoint) -> String)?

    @State private var uiImage: UIImage?
    @State private var crosshair = CoordinateEngine.PixelPoint(x: 0, y: 0)
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var placementMode = true
    @State private var saveMessage: String?
    @State private var containerSize: CGSize = .zero

    private var nativeSize: CGSize {
        CGSize(width: widthPx, height: heightPx)
    }

    private var displayRect: CGRect {
        CoordinateEngine.aspectFitRect(imageSize: nativeSize, container: containerSize)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let uiImage = uiImage {
                    viewerContent(uiImage: uiImage)
                } else {
                    ProgressView().tint(.white)
                }
                coordinateReadout
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: Alignment(horizontal: .leading, vertical: .bottom))
                    .padding(.bottom, 8)
            }
            .onAppear {
                containerSize = geo.size
                if uiImage == nil {
                    uiImage = ImageToolkit.uiImage(from: imageData)
                    crosshair = CoordinateEngine.PixelPoint(x: widthPx / 2, y: heightPx / 2)
                }
            }
            .onChange(of: geo.size) { newSize in
                containerSize = newSize
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    placementMode.toggle()
                } label: {
                    Image(systemName: placementMode ? "target" : "hand.draw")
                }
                .help(placementMode ? "Switch to pan mode" : "Switch to crosshair mode")

                Menu {
                    Stepper(value: Binding(
                        get: { crosshair.x },
                        set: { crosshair.x = CoordinateEngine.clamp($0, 0, max(1, widthPx - 1)) }),
                        in: 0...max(1, widthPx - 1)) {
                        Text("x = \(crosshair.x) px")
                    }
                    Stepper(value: Binding(
                        get: { crosshair.y },
                        set: { crosshair.y = CoordinateEngine.clamp($0, 0, max(1, heightPx - 1)) }),
                        in: 0...max(1, heightPx - 1)) {
                        Text("y = \(crosshair.y) px")
                    }
                    Button("Reset zoom") {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                if let onSave = onSave {
                    Button("Save") {
                        saveMessage = onSave(crosshair)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func viewerContent(uiImage: UIImage) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .frame(width: displayRect.width, height: displayRect.height)
                .overlay(
                    CrosshairOverlay(
                        imageDisplaySize: displayRect.size,
                        imagePixelSize: nativeSize,
                        point: $crosshair,
                        consensusPoint: consensusPoint,
                        otherJudges: otherJudges,
                        interactive: placementMode)
                )
                .offset(x: displayRect.origin.x, y: displayRect.origin.y)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .scaleEffect(scale, anchor: .center)
        .offset(offset)
        .gesture(magnificationGesture)
        .simultaneousGesture(panGesture)
        .onTapGesture(count: 2) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let candidate = lastScale * value
                scale = CGFloat(candidate.clampedTo(1.0...10.0))
            }
            .onEnded { _ in
                lastScale = scale
                clampOffset()
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: placementMode ? 60 : 0)
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
                clampOffset()
            }
    }

    private func clampOffset() {
        let maxX = Double((scale - 1) * displayRect.width / 2)
        let maxY = Double((scale - 1) * displayRect.height / 2)
        offset = CGSize(width: offset.width.clampedTo(-maxX...maxX),
                        height: offset.height.clampedTo(-maxY...maxY))
        lastOffset = offset
    }

    private var coordinateReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("(\(crosshair.x), \(crosshair.y)) px  native \(widthPx)×\(heightPx)")
                .font(.caption.monospaced().bold())
            if let n = try? CoordinateEngine.toNormalized(crosshair, width: widthPx, height: heightPx) {
                Text(String(format: "normalized %.4f, %.4f   zoom %.1f× %@", n.0, n.1, scale,
                            placementMode ? "crosshair mode" : "pan mode"))
                    .font(.caption2.monospaced())
            }
            if let msg = saveMessage {
                Text(msg).font(.caption2.monospaced()).foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 8)
    }
}
