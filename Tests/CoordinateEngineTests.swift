// CoordinateEngineTests.swift
// Engine regression contract (spec section 7) pinned to Python vectors.

import XCTest
import CoreGraphics
@testable import PrivateJudgesWorkspace

final class CoordinateEngineTests: XCTestCase {

    // MARK: rounding parity (incl. negative half-integers)

    func testRoundHalfEvenMatchesPythonVectors() throws {
        let vectors = try Fixtures.referenceVectors()
        let rounding = try XCTUnwrap(vectors["rounding_vectors"]?.arrayValue)
        for spec in rounding {
            let dict = try XCTUnwrap(spec.objectValue)
            let v = try XCTUnwrap(dict["v"]?.doubleValue)
            let expected = try XCTUnwrap(dict["rounded"]?.intValue)
            XCTAssertEqual(CoordinateEngine.roundHalfEven(v), expected,
                           "half-even mismatch for \(v)")
        }
    }

    // MARK: P -> N -> P round trip

    func testRoundTripWithinOnePixelMatchesPythonVectors() throws {
        let vectors = try Fixtures.referenceVectors()
        let cases = try XCTUnwrap(vectors["roundtrip_vectors"]?.arrayValue)
        for spec in cases {
            let dict = try XCTUnwrap(spec.objectValue)
            let w = try XCTUnwrap(dict["w"]?.intValue)
            let h = try XCTUnwrap(dict["h"]?.intValue)
            let x = try XCTUnwrap(dict["x"]?.intValue)
            let y = try XCTUnwrap(dict["y"]?.intValue)
            let nx = try XCTUnwrap(dict["nx"]?.doubleValue)
            let ny = try XCTUnwrap(dict["ny"]?.doubleValue)
            let expectedRx = try XCTUnwrap(dict["rx"]?.intValue)
            let expectedRy = try XCTUnwrap(dict["ry"]?.intValue)

            let p = CoordinateEngine.PixelPoint(x: x, y: y)
            let normalized = try CoordinateEngine.toNormalized(p, width: w, height: h)
            XCTAssertEqual(normalized.0, nx, accuracy: 1e-15)
            XCTAssertEqual(normalized.1, ny, accuracy: 1e-15)
            let q = try CoordinateEngine.fromNormalized(nx, ny, width: w, height: h)
            XCTAssertEqual(q.x, expectedRx)
            XCTAssertEqual(q.y, expectedRy)
            let err = try CoordinateEngine.roundtripErrorPx(p, width: w, height: h)
            XCTAssertLessThanOrEqual(err.0, 1)
            XCTAssertLessThanOrEqual(err.1, 1)
        }
    }

    // MARK: bounds and validation

    func testBoundsRejectionAndClamping() throws {
        let identity = CoordinateEngine.ImageIdentity(sha256: String(repeating: "a", count: 64),
                                                      widthPx: 100, heightPx: 100)
        XCTAssertThrowsError(try identity.validate(
            pointInside: CoordinateEngine.PixelPoint(x: 100, y: 50)))
        XCTAssertThrowsError(try identity.validate(
            pointInside: CoordinateEngine.PixelPoint(x: 50, y: -1)))
        XCTAssertNoThrow(try identity.validate(
            pointInside: CoordinateEngine.PixelPoint(x: 99, y: 99)))

        // fromNormalized clamps into bounds
        let p = try CoordinateEngine.fromNormalized(-0.5, 1.5, width: 100, height: 100)
        XCTAssertEqual(p.x, 0)
        XCTAssertEqual(p.y, 99)

        XCTAssertThrowsError(try CoordinateEngine.fromNormalized(.nan, 0.5, width: 100, height: 100))
        XCTAssertThrowsError(try CoordinateEngine.fromNormalized(0.5, 0.5, width: 1, height: 100))
        XCTAssertThrowsError(try CoordinateEngine.toNormalized(
            CoordinateEngine.PixelPoint(x: 0, y: 0), width: 0, height: 10))
    }

    func testIdentifierValidation() {
        XCTAssertNoThrow(try CoordinateEngine.validateIdentifier("PJV-2026_R1.a"))
        XCTAssertThrowsError(try CoordinateEngine.validateIdentifier(""))
        XCTAssertThrowsError(try CoordinateEngine.validateIdentifier("bad id"))
        XCTAssertThrowsError(try CoordinateEngine.validateIdentifier(String(repeating: "x", count: 129)))
    }

    // MARK: distances

    func testDistanceVectors345() throws {
        let vectors = try Fixtures.referenceVectors()
        for spec in try XCTUnwrap(vectors["distance_vectors"]?.arrayValue) {
            let dict = try XCTUnwrap(spec.objectValue)
            let a = CoordinateEngine.PixelPoint(x: try XCTUnwrap(dict["ax"]?.intValue),
                                                y: try XCTUnwrap(dict["ay"]?.intValue))
            let b = CoordinateEngine.PixelPoint(x: try XCTUnwrap(dict["bx"]?.intValue),
                                                y: try XCTUnwrap(dict["by"]?.intValue))
            let expected = try XCTUnwrap(dict["distance"]?.doubleValue)
            XCTAssertEqual(CoordinateEngine.euclideanDistancePx(a, b), expected, accuracy: 1e-12)
        }
        let nd = try CoordinateEngine.normalizedDistance(
            CoordinateEngine.PixelPoint(x: 0, y: 0), CoordinateEngine.PixelPoint(x: 3, y: 4),
            width: 1920, height: 1080)
        let ndExpected = try XCTUnwrap(vectors["normalized_distance_vectors"]?.arrayValue?.first?
            .objectValue?["nd"]?.doubleValue)
        XCTAssertEqual(nd, try XCTUnwrap(ndExpected), accuracy: 1e-15)
    }

    // MARK: consensus parity (byte-exact dict against Python)

    func testConsensusDictsMatchPythonByteForByte() throws {
        let vectors = try Fixtures.referenceVectors()
        let cases = try XCTUnwrap(vectors["consensus_vectors"]?.arrayValue)
        for spec in cases {
            let dict = try XCTUnwrap(spec.objectValue)
            let name = try XCTUnwrap(dict["name"]?.stringValue)
            let points = try XCTUnwrap(dict["points"]?.arrayValue).map {
                CoordinateEngine.PixelPoint(
                    x: try XCTUnwrap($0.arrayValue?[0].intValue),
                    y: try XCTUnwrap($0.arrayValue?[1].intValue))
            }
            let tolerance = try XCTUnwrap(dict["tolerance_px"]?.doubleValue)
            let method = try XCTUnwrap(dict["method"]?.stringValue)
            let expectedCanonical = try XCTUnwrap(dict["canonical"]?.stringValue)
            let expectedHash = try XCTUnwrap(dict["hash"]?.stringValue)

            let produced = try CoordinateEngine.evaluateConsensusDict(
                points, tolerancePx: tolerance, method: method)
            XCTAssertEqual(CanonicalJSON.string(produced), expectedCanonical,
                           "consensus canonical mismatch in \(name)")
            XCTAssertEqual(CanonicalJSON.hash(produced), expectedHash,
                           "consensus hash mismatch in \(name)")
        }
    }

    func testConsensusDeterminismAndOutlierRobustness() throws {
        // Determinism: repeated calls identical.
        let cluster = [CoordinateEngine.PixelPoint(x: 100, y: 100),
                       CoordinateEngine.PixelPoint(x: 102, y: 98),
                       CoordinateEngine.PixelPoint(x: 99, y: 101),
                       CoordinateEngine.PixelPoint(x: 101, y: 99)]
        let first = try CoordinateEngine.consensus(cluster)
        for _ in 0..<5 {
            XCTAssertEqual(try CoordinateEngine.consensus(cluster), first)
        }

        // Outlier robustness (same geometry as the Python regression suite):
        // a far outlier must move the consensus by less than 5 px.
        let withOutlier = cluster + [CoordinateEngine.PixelPoint(x: 500, y: 500)]
        let shifted = try CoordinateEngine.consensus(withOutlier)
        XCTAssertLessThan(CoordinateEngine.euclideanDistancePx(first, shifted), 5.0)
    }

    func testUnknownMethodAndEmptyInputRejected() {
        XCTAssertThrowsError(try CoordinateEngine.consensus(
            [CoordinateEngine.PixelPoint(x: 1, y: 1)], method: "fancy_average"))
        XCTAssertThrowsError(try CoordinateEngine.consensus([]))
    }

    // MARK: display mapping (UI-space helpers)

    func testAspectFitAndPixelMapping() throws {
        let rect = CoordinateEngine.aspectFitRect(imageSize: CGSize(width: 2000, height: 1000),
                                                  container: CGSize(width: 100, height: 100))
        XCTAssertEqual(rect.width, 100, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 50, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.y, 25, accuracy: 1e-9)

        // view point in the centre of the fitted rect -> centre pixel
        let centreView = CGPoint(x: rect.midX, y: rect.midY)
        let p = try CoordinateEngine.pixelFromViewPoint(centreView, displayRect: rect,
                                                        nativeSize: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(p.x, 1000)
        XCTAssertEqual(p.y, 500)
        let back = CoordinateEngine.viewPointFromPixel(p, displayRect: rect,
                                                       nativeSize: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(back.x, centreView.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, centreView.y, accuracy: 1e-9)
    }
}
