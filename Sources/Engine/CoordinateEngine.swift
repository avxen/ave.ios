// CoordinateEngine.swift
// Private Judges Workspace - Authoritative Coordinate Engine (Swift port)
//
// MIRRORS engine/coordinate_engine.py rule-for-rule:
//   - P space: integer pixels, origin top-left, x right, y down (CANONICAL)
//   - N space: x_n = x / W, y_n = y / H in [0, 1)
//   - round-half-to-even on inverse mapping, then clamp
//   - geometric median via Weiszfeld (maxIter 100, tol 1e-7, eps 1e-9)
//   - distances Euclidean in pixels (hypot, as in the reference)
//   - consensus dict values rounded like the reference:
//       raw_x/raw_y -> 6 decimals, max_spread_px -> 3, agreement_ratio -> 4
//
// Parity notes (docs/PARITY_NOTES.md):
//   - roundHalfEven selects the EVEN NEIGHBOUR for exact .5 cases, including
//     negative inputs (Python round() semantics). The original scaffold port
//     diverged from Python for negative half-integers; this implementation
//     fixes that and is pinned by Tests/Fixtures/reference_vectors.json.
//
// Every screen that places, adjusts, stores, reopens, compares or verifies a
// crosshair MUST route through this engine. No feature keeps a private
// coordinate representation.

import Foundation
import CryptoKit
import CoreGraphics

public enum CoordinateEngine {
    public static let engineVersion = "1.0.0"
    public static let weiszfeldMaxIter = 100
    public static let weiszfeldTol = 1e-7
    static let eps = 1e-9

    public enum CoordinateError: Error, Equatable {
        case outsideBounds
        case invalidDimensions
        case invalidInput
        case noPoints
        case unknownMethod(String)
        case invalidIdentifier
    }

    // MARK: - Hashing

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Image identity: SHA-256 of the raw image bytes.
    public static func imageSHA256(_ data: Data) -> String {
        sha256Hex(data)
    }

    // MARK: - Points, identity and conversions

    public struct PixelPoint: Equatable, Hashable, Codable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct ImageIdentity: Equatable {
        public let sha256: String
        public let widthPx: Int
        public let heightPx: Int

        public init(data: Data, widthPx: Int, heightPx: Int) {
            self.sha256 = CoordinateEngine.imageSHA256(data)
            self.widthPx = widthPx
            self.heightPx = heightPx
        }

        public init(sha256: String, widthPx: Int, heightPx: Int) {
            self.sha256 = sha256
            self.widthPx = widthPx
            self.heightPx = heightPx
        }

        /// Identity rules from the spec: dimensions >= 2, lowercase hex digest.
        public func validate() throws {
            let hexOK = sha256.count == 64 && sha256.allSatisfy { c in
                guard let a = c.asciiValue else { return false }
                return (48...57).contains(a) || (97...102).contains(a)
            }
            guard hexOK else { throw CoordinateError.invalidInput }
            guard widthPx >= 2, heightPx >= 2 else { throw CoordinateError.invalidDimensions }
        }

        public func validate(pointInside p: PixelPoint) throws {
            try validate()
            guard p.x >= 0, p.x < widthPx, p.y >= 0, p.y < heightPx else {
                throw CoordinateError.outsideBounds
            }
        }
    }

    /// Identifiers match ^[A-Za-z0-9._-]{1,128}$ (mirror of crosshair_records).
    public static func validateIdentifier(_ value: String) throws {
        let allowed = value.allSatisfy { char in
            (char.isASCII && (char.isLetter || char.isNumber)) ||
            char == "." || char == "_" || char == "-"
        }
        guard !value.isEmpty, value.count <= 128, allowed else {
            throw CoordinateError.invalidIdentifier
        }
    }

    public static func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, value))
    }

    /// Round-half-to-even, then clamp. Round-trip error is at most 1 px/axis.
    /// Even-neighbour selection works for negative inputs too (Python round()).
    static func roundHalfEven(_ v: Double) -> Int {
        guard v.isFinite, abs(v) < 1e15 else { return 0 }
        if abs(v - v.rounded(.towardZero)) == 0.5 {
            // exact .5 case: choose the even neighbour
            let below = Foundation.floor(v)
            let above = Foundation.ceil(v)
            let belowEven = Int(below).isMultiple(of: 2)
            return Int(belowEven ? below : above)
        }
        return Int(v.rounded(.toNearestOrAwayFromZero))
    }

    /// Python round(x, digits) for margin-safe values (see PARITY_NOTES.md).
    static func roundTo(_ v: Double, _ digits: Int) -> Double {
        let factor = pow(10.0, Double(digits))
        return (v * factor).rounded(.toNearestOrAwayFromZero) / factor
    }

    public static func toNormalized(_ p: PixelPoint, width: Int, height: Int)
        throws -> (Double, Double) {
        guard width >= 2, height >= 2 else { throw CoordinateError.invalidDimensions }
        guard p.x >= 0, p.x < width, p.y >= 0, p.y < height else {
            throw CoordinateError.outsideBounds
        }
        return (Double(p.x) / Double(width), Double(p.y) / Double(height))
    }

    public static func fromNormalized(_ nx: Double, _ ny: Double,
                                      width: Int, height: Int) throws -> PixelPoint {
        guard width >= 2, height >= 2 else { throw CoordinateError.invalidDimensions }
        guard nx.isFinite, ny.isFinite, nx >= -1.0, nx <= 2.0, ny >= -1.0, ny <= 2.0 else {
            throw CoordinateError.invalidInput
        }
        return PixelPoint(x: clamp(roundHalfEven(nx * Double(width)), 0, width - 1),
                          y: clamp(roundHalfEven(ny * Double(height)), 0, height - 1))
    }

    public static func roundtripErrorPx(_ p: PixelPoint, width: Int, height: Int)
        throws -> (Int, Int) {
        let (nx, ny) = try toNormalized(p, width: width, height: height)
        let q = try fromNormalized(nx, ny, width: width, height: height)
        return (abs(q.x - p.x), abs(q.y - p.y))
    }

    // MARK: - Distances

    public static func euclideanDistancePx(_ a: PixelPoint, _ b: PixelPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    public static func normalizedDistance(_ a: PixelPoint, _ b: PixelPoint,
                                          width: Int, height: Int) throws -> Double {
        let diag = hypot(Double(width), Double(height))
        guard diag > 0 else { throw CoordinateError.invalidDimensions }
        return euclideanDistancePx(a, b) / diag
    }

    // MARK: - Consensus

    public static func perAxisMedian(_ points: [PixelPoint]) throws -> PixelPoint {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        let xs = points.map(\.x).sorted()
        let ys = points.map(\.y).sorted()
        let n = points.count
        let mx: Int
        if n % 2 == 1 { mx = xs[n / 2] }
        else { mx = roundHalfEven(Double(xs[n / 2 - 1] + xs[n / 2]) / 2.0) }
        let my: Int
        if n % 2 == 1 { my = ys[n / 2] }
        else { my = roundHalfEven(Double(ys[n / 2 - 1] + ys[n / 2]) / 2.0) }
        return PixelPoint(x: mx, y: my)
    }

    /// Weiszfeld iteration from the per-axis median; deterministic.
    public static func geometricMedian(_ points: [PixelPoint]) throws -> (Double, Double) {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        let med = try perAxisMedian(points)
        var fx = Double(med.x), fy = Double(med.y)
        for _ in 0..<weiszfeldMaxIter {
            var wsum = 0.0, sx = 0.0, sy = 0.0
            for p in points {
                let d = max(hypot(Double(p.x) - fx, Double(p.y) - fy), eps)
                let w = 1.0 / d
                wsum += w
                sx += w * Double(p.x)
                sy += w * Double(p.y)
            }
            let nx = sx / wsum, ny = sy / wsum
            let stepDistance = hypot(nx - fx, ny - fy)
            fx = nx; fy = ny
            if stepDistance < weiszfeldTol { break }
        }
        return (fx, fy)
    }

    public static func pairwiseMaxSpread(_ points: [PixelPoint]) -> Double {
        guard points.count > 1 else { return 0.0 }
        var worst = 0.0
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                worst = max(worst, euclideanDistancePx(points[i], points[j]))
            }
        }
        return worst
    }

    public static func withinTolerance(_ a: PixelPoint, _ b: PixelPoint,
                                       tolerancePx: Double) -> Bool {
        precondition(tolerancePx >= 0, "tolerance must be >= 0")
        return euclideanDistancePx(a, b) <= tolerancePx
    }

    public static func agreementRatio(_ points: [PixelPoint], consensusPoint: PixelPoint,
                                      tolerancePx: Double) throws -> Double {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        let hits = points.filter { withinTolerance($0, consensusPoint, tolerancePx: tolerancePx) }.count
        return Double(hits) / Double(points.count)
    }

    public static func consensus(_ points: [PixelPoint],
                                 method: String = "geometric_median") throws -> PixelPoint {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        switch method {
        case "geometric_median":
            let raw = try geometricMedian(points)
            return PixelPoint(x: roundHalfEven(raw.0), y: roundHalfEven(raw.1))
        case "per_axis_median":
            return try perAxisMedian(points)
        default:
            throw CoordinateError.unknownMethod(method)
        }
    }

    /// Full consensus evaluation dict, mirroring evaluate_consensus() output
    /// exactly (key set, value types and rounding).
    static func evaluateConsensusDict(_ points: [PixelPoint], tolerancePx: Double,
                                      method: String = "geometric_median")
        throws -> CanonicalValue {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        let point = try consensus(points, method: method)
        let raw: (Double, Double)
        switch method {
        case "geometric_median": raw = try geometricMedian(points)
        case "per_axis_median":
            let m = try perAxisMedian(points); raw = (Double(m.x), Double(m.y))
        default:
            throw CoordinateError.unknownMethod(method)
        }
        let ratio = try agreementRatio(points, consensusPoint: point, tolerancePx: tolerancePx)
        return .object([
            ("method", .string(method)),
            ("x_px", .int(point.x)),
            ("y_px", .int(point.y)),
            ("raw_x", .double(roundTo(raw.0, 6))),
            ("raw_y", .double(roundTo(raw.1, 6))),
            ("engine_version", .string(engineVersion)),
            ("tolerance_px", .double(tolerancePx)),
            ("max_spread_px", .double(roundTo(pairwiseMaxSpread(points), 3))),
            ("agreement_ratio", .double(roundTo(ratio, 4))),
            ("n_judges", .int(points.count)),
        ])
    }

    /// Typed view over the consensus evaluation, used by the UI.
    public struct ConsensusEvaluation {
        public let method: String
        public let xPx: Int
        public let yPx: Int
        public let rawX: Double
        public let rawY: Double
        public let tolerancePx: Double
        public let maxSpreadPx: Double
        public let agreementRatio: Double
        public let nJudges: Int

        var canonicalDict: CanonicalValue {
            .object([
                ("method", .string(method)),
                ("x_px", .int(xPx)),
                ("y_px", .int(yPx)),
                ("raw_x", .double(rawX)),
                ("raw_y", .double(rawY)),
                ("engine_version", .string(engineVersion)),
                ("tolerance_px", .double(tolerancePx)),
                ("max_spread_px", .double(maxSpreadPx)),
                ("agreement_ratio", .double(agreementRatio)),
                ("n_judges", .int(nJudges)),
            ])
        }
    }

    public static func evaluateConsensus(_ points: [PixelPoint], tolerancePx: Double,
                                         method: String = "geometric_median")
        throws -> ConsensusEvaluation {
        guard !points.isEmpty else { throw CoordinateError.noPoints }
        let point = try consensus(points, method: method)
        let raw: (Double, Double)
        switch method {
        case "geometric_median": raw = try geometricMedian(points)
        case "per_axis_median":
            let m = try perAxisMedian(points); raw = (Double(m.x), Double(m.y))
        default:
            throw CoordinateError.unknownMethod(method)
        }
        let ratio = try agreementRatio(points, consensusPoint: point, tolerancePx: tolerancePx)
        return ConsensusEvaluation(method: method, xPx: point.x, yPx: point.y,
                                   rawX: roundTo(raw.0, 6), rawY: roundTo(raw.1, 6),
                                   tolerancePx: tolerancePx,
                                   maxSpreadPx: roundTo(pairwiseMaxSpread(points), 3),
                                   agreementRatio: roundTo(ratio, 4),
                                   nJudges: points.count)
    }

    // MARK: - Display mapping (UI-space conversions; UI never converts privately)

    /// Aspect-fit rectangle of an image of `imageSize` points inside `container`.
    public static func aspectFitRect(imageSize: CGSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale,
                          height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Container view point -> canonical pixel. The single conversion path used
    /// by every crosshair screen (view -> normalized -> pixel via the engine).
    public static func pixelFromViewPoint(_ viewPoint: CGPoint, displayRect: CGRect,
                                          nativeSize: CGSize) throws -> PixelPoint {
        guard displayRect.width > 0, displayRect.height > 0,
              nativeSize.width >= 2, nativeSize.height >= 2 else {
            throw CoordinateError.invalidDimensions
        }
        let nx = Double((viewPoint.x - displayRect.origin.x) / displayRect.width)
        let ny = Double((viewPoint.y - displayRect.origin.y) / displayRect.height)
        return try fromNormalized(nx, ny,
                                  width: Int(nativeSize.width),
                                  height: Int(nativeSize.height))
    }

    /// Canonical pixel -> container view point (crosshair rendering).
    public static func viewPointFromPixel(_ p: PixelPoint, displayRect: CGRect,
                                          nativeSize: CGSize) -> CGPoint {
        guard nativeSize.width >= 1, nativeSize.height >= 1, displayRect.width > 0 else {
            return displayRect.origin
        }
        return CGPoint(x: displayRect.origin.x +
                          (Double(p.x) / Double(Int(nativeSize.width))) * displayRect.width,
                       y: displayRect.origin.y +
                          (Double(p.y) / Double(Int(nativeSize.height))) * displayRect.height)
    }
}
