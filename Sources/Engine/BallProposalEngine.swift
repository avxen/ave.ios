// BallProposalEngine.swift
// Private Judges Workspace - computer-assisted ball-position proposals.
//
// HONEST SCOPE: this is a deterministic heuristic blob detector (dark
// circular-object search over a downscaled luminance grid with an integral
// image). It is NOT a machine-learning model. Its output is advisory:
// proposals are stored in ai_proposals[] only, never in judges[], and can
// never influence the consensus computation. The UI labels every proposal as
// "computer-generated proposal - not observed evidence".

import Foundation
import CoreGraphics

struct ProposalCandidate: Equatable, Identifiable {
    var xPx: Int
    var yPx: Int
    var confidence: Double
    var model: String
    var id: String { "\(model)-\(xPx)-\(yPx)" }
}

enum BallProposalEngine {

    static let modelId = "heuristic-blob-v1"

    /// Generate ranked ball-position proposals for an image.
    /// - Parameters:
    ///   - cgImage: native-resolution image
    ///   - maxProposals: number of candidates returned (after suppression)
    /// - Returns: proposals in native pixel coordinates (via the coordinate
    ///   engine; never raw view coordinates).
    static func proposals(cgImage: CGImage, maxProposals: Int = 3) -> [ProposalCandidate] {
        let grid = luminanceGrid(from: cgImage, maxDimension: 320)
        guard grid.w >= 8, grid.h >= 8, grid.pixels.count == grid.w * grid.h else { return [] }

        let integral = summedAreaTable(grid.pixels, width: grid.w, height: grid.h)
        let integralSq = summedAreaTable(grid.pixels.map { $0 * $0 }, width: grid.w, height: grid.h)

        let minSide = min(grid.w, grid.h)
        let radii = [max(2, minSide / 64), max(3, minSide / 40), max(4, minSide / 24)]
        var candidates: [(x: Int, y: Int, score: Double)] = []

        for r in radii {
            guard 2 * r + 1 <= min(grid.w, grid.h) else { continue }
            for cy in r..<(grid.h - r) {
                for cx in r..<(grid.w - r) {
                    let centerMean = boxMean(integral, width: grid.w,
                                             x0: cx - r, y0: cy - r, x1: cx + r, y1: cy + r)
                    let outer = boxMean(integral, width: grid.w,
                                        x0: cx - 2 * r, y0: cy - 2 * r,
                                        x1: cx + 2 * r, y1: cy + 2 * r)
                    let centerCount = (2 * r + 1) * (2 * r + 1)
                    let outerCount = (4 * r + 1) * (4 * r + 1)
                    let ringMean = (outer * Double(outerCount) - centerMean * Double(centerCount))
                        / Double(outerCount - centerCount)
                    // dark circular blob: centre notably darker than ring
                    let contrast = ringMean - centerMean
                    guard contrast > 0.02 else { continue }
                    let localStd = boxStd(integral, integralSq, width: grid.w,
                                          x0: cx - 2 * r, y0: cy - 2 * r,
                                          x1: cx + 2 * r, y1: cy + 2 * r)
                    let score = contrast / (localStd + 0.02)
                    candidates.append((cx, cy, score))
                }
            }
        }

        // Non-maximum suppression and ranking.
        candidates.sort { $0.score > $1.score }
        var selected: [(x: Int, y: Int, score: Double)] = []
        let separation = max(4, minSide / 16)
        for cand in candidates {
            if selected.count >= maxProposals { break }
            let farEnough = selected.allSatisfy {
                hypot(Double($0.x - cand.x), Double($0.y - cand.y)) >= Double(separation)
            }
            if farEnough { selected.append(cand) }
        }

        // Map grid cells -> native pixels strictly through the coordinate engine.
        return selected.compactMap { cand in
            let nx = Double(cand.x + 0.5) / Double(grid.w)
            let ny = Double(cand.y + 0.5) / Double(grid.h)
            guard let p = try? CoordinateEngine.fromNormalized(
                nx, ny, width: cgImage.width, height: cgImage.height) else { return nil }
            let confidence = min(0.99, max(0.05, cand.score / 6.0))
            return ProposalCandidate(xPx: p.x, yPx: p.y,
                                     confidence: (confidence * 100).rounded() / 100,
                                     model: modelId)
        }
    }

    // MARK: - luminance grid

    struct Grid {
        let pixels: [Double]
        let w: Int
        let h: Int
    }

    /// Downscaled luminance grid [0,1] (Rec. 601 weights), CoreGraphics-drawn.
    static func luminanceGrid(from image: CGImage, maxDimension: Int) -> Grid {
        let nativeW = image.width, nativeH = image.height
        guard nativeW >= 2, nativeH >= 2 else { return Grid(pixels: [], w: 0, h: 0) }
        let scale = min(1.0, Double(maxDimension) / Double(max(nativeW, nativeH)))
        let w = max(2, Int((Double(nativeW) * scale).rounded()))
        let h = max(2, Int((Double(nativeH) * scale).rounded()))

        guard let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return Grid(pixels: [], w: 0, h: 0) }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return Grid(pixels: [], w: 0, h: 0) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h)
        var pixels = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) { pixels[i] = Double(bytes[i]) / 255.0 }
        return Grid(pixels: pixels, w: w, h: h)
    }

    // MARK: - integral image helpers

    /// Summed-area table with a 1-pixel border so box sums stay in-bounds.
    static func summedAreaTable(_ pixels: [Double], width: Int, height: Int) -> [Double] {
        var table = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            for x in 0..<width {
                rowSum += pixels[y * width + x]
                table[(y + 1) * (width + 1) + (x + 1)] =
                    table[y * (width + 1) + (x + 1)] + rowSum
            }
        }
        return table
    }

    static func boxSum(_ table: [Double], width: Int,
                       x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
        let w = width + 1
        let x0c = max(0, x0), y0c = max(0, y0)
        let x1c = min(width - 1, x1), y1c = min(height(table, w) - 2, y1)
        let a = y0c * w + x0c
        let b = y0c * w + (x1c + 1)
        let c = (y1c + 1) * w + x0c
        let d = (y1c + 1) * w + (x1c + 1)
        return table[d] - table[b] - table[c] + table[a]
    }

    private static func height(_ table: [Double], _ w: Int) -> Int {
        table.count / w
    }

    static func boxMean(_ table: [Double], width: Int,
                        x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
        let x0c = max(0, x0), y0c = max(0, y0)
        let x1c = min(width - 1, x1)
        let h = max(0, y1c - y0c + 1), wid = max(0, x1c - x0c + 1)
        guard h > 0, wid > 0 else { return 0 }
        return boxSum(table, width: width, x0: x0c, y0: y0c, x1: x1c, y1: y1c)
            / Double(h * wid)
    }

    static func boxStd(_ integral: [Double], _ integralSq: [Double], width: Int,
                       x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
        let x0c = max(0, x0), y0c = max(0, y0)
        let x1c = min(width - 1, x1)
        let h = max(0, y1c - y0c + 1), wid = max(0, x1c - x0c + 1)
        guard h > 0, wid > 0 else { return 0 }
        let n = Double(h * wid)
        let mean = boxSum(integral, width: width, x0: x0c, y0: y0c, x1: x1c, y1: y1c) / n
        let meanSq = boxSum(integralSq, width: width, x0: x0c, y0: y0c, x1: x1c, y1: y1c) / n
        return sqrt(max(0, meanSq - mean * mean))
    }
}
