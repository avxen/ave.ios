// CanonicalJSONTests.swift
// Byte-parity of the canonical serializer with the Python reference.

import XCTest
@testable import PrivateJudgesWorkspace

final class CanonicalJSONTests: XCTestCase {

    func testCanonicalVectorsMatchPython() throws {
        let vectors = try Fixtures.referenceVectors()
        let cases = try XCTUnwrap(vectors["canonical_vectors"]?.arrayValue)
        for (index, caseValue) in cases.enumerated() {
            let spec = try XCTUnwrap(caseValue.objectValue, "vector \(index)")
            let input = try XCTUnwrap(spec["input"])
            let expectedCanonical = try XCTUnwrap(spec["canonical"]?.stringValue)
            let expectedHash = try XCTUnwrap(spec["hash"]?.stringValue)
            let produced = CanonicalJSON.string(input.canonical)
            XCTAssertEqual(produced, expectedCanonical,
                           "canonical mismatch in vector \(index)")
            XCTAssertEqual(CanonicalJSON.hash(input.canonical), expectedHash,
                           "hash mismatch in vector \(index)")
        }
    }

    func testIntegralDoubleKeepsPythonFloatSuffix() {
        XCTAssertEqual(CanonicalJSON.doubleRepr(12.0), "12.0")
        XCTAssertEqual(CanonicalJSON.doubleRepr(0.1), "0.1")
        XCTAssertEqual(CanonicalJSON.doubleRepr(8.485), "8.485")
        XCTAssertEqual(CanonicalJSON.doubleRepr(512.000004), "512.000004")
        XCTAssertEqual(CanonicalJSON.string(.object([("z", .double(12.0))])),
                       "{\"z\":12.0}")
        XCTAssertEqual(CanonicalJSON.string(.object([("z", .int(12))])),
                       "{\"z\":12}")
    }

    func testKeySortingAndEscaping() {
        let value = CanonicalValue.object([
            ("b", .string("line\nquote\"slash\\")),
            ("a", .int(1)),
            ("A", .bool(true)),
            ("_", .null),
        ])
        XCTAssertEqual(CanonicalJSON.string(value),
                       "{\"A\":true,\"_\":null,\"a\":1,\"b\":\"line\\nquote\\\"slash\\\\\"}")
    }

    func testUnicodeEmittedRaw() {
        let value = CanonicalValue.object([("k", .string("كرة ⚽"))])
        let s = CanonicalJSON.string(value)
        XCTAssertTrue(s.contains("كرة"), "non-ASCII must not be escaped")
        XCTAssertFalse(s.contains("\\u0"))
    }
}
