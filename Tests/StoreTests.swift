// StoreTests.swift
// Records + assessments: save/reopen/verify, tamper detection, encryption,
// and cross-language interop with Python-produced records.

import XCTest
@testable import PrivateJudgesWorkspace

final class RecordsStoreTests: XCTestCase {

    private func tempRoot(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-tests-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleRecord() -> CrosshairRecordFile {
        CrosshairRecordFile(competitionId: "PJV-2026-R1", judgeId: "JUDGE-01",
                            imageId: String(repeating: "a", count: 64),
                            imageWidthPx: 1920, imageHeightPx: 1080,
                            xPx: 1234, yPx: 567, note: "near centre circle",
                            createdAt: "2026-11-21T10:00:00Z",
                            engineVersion: CoordinateEngine.engineVersion)
    }

    func testSaveLoadRoundTripEncrypted() throws {
        let store = RecordsStore(root: tempRoot("records"), vault: Vault.ephemeralVault())
        let recordId = try store.save(record: sampleRecord())
        let expected = try XCTUnwrap(
            Fixtures.referenceVectors()["record_vectors"]?.arrayValue?.first?
                .objectValue?["record_id"]?.stringValue)
        XCTAssertEqual(recordId, expected, "record id must equal the Python reference id")

        let loaded = try store.load(recordId: recordId)
        XCTAssertEqual(loaded, sampleRecord())
        XCTAssertEqual(store.listRecordIds(), [recordId])

        let report = try store.verify(recordId: recordId, identity: nil)
        XCTAssertEqual(report.status, .pass)
    }

    func testRecordHashMatchesPythonVectors() throws {
        let vectors = try Fixtures.referenceVectors()
        let cases = try XCTUnwrap(vectors["record_vectors"]?.arrayValue)
        for spec in cases {
            let dict = try XCTUnwrap(spec.objectValue)
            let payload = try XCTUnwrap(dict["payload"]?.objectValue)
            let expectedId = try XCTUnwrap(dict["record_id"]?.stringValue)
            // hash of the payload WITHOUT record_id (mirrors crosshair_records)
            let withoutId = payload.filter { $0.key != "record_id" }
                .map { ($0.key, $0.value.canonical) }
            XCTAssertEqual(CanonicalJSON.hash(.object(withoutId)), expectedId)
            XCTAssertEqual(payload["record_id"]?.stringValue, expectedId,
                           "payload must embed the same record id")
        }
    }

    func testExportJSONMatchesCanonicalForm() throws {
        let store = RecordsStore(root: tempRoot("export"), vault: Vault.ephemeralVault())
        let recordId = try store.save(record: sampleRecord())
        let exported = try store.exportJSON(recordId: recordId)
        let reparsed = try JSONValue.parse(exported)
        let dict = try XCTUnwrap(reparsed.objectValue)
        XCTAssertEqual(dict["record_id"]?.stringValue, recordId)
        XCTAssertEqual(dict["x_px"]?.intValue, 1234)
        // digest of the canonical payload (without record_id) still matches
        let payload = dict.filter { $0.key != "record_id" }
        XCTAssertEqual(CanonicalJSON.hash(.object(payload.map { ($0.key, $0.value.canonical) })),
                       recordId)
    }

    func testTamperedRecordRejected() throws {
        let store = RecordsStore(root: tempRoot("tamper"), vault: Vault.ephemeralVault())
        let recordId = try store.save(record: sampleRecord())
        // tamper with the sealed file: contents no longer decrypt/verify
        let url = store.root.appendingPathComponent(recordId + ".rec")
        try Data([0x00, 0x01, 0x02]).write(to: url)
        XCTAssertThrowsError(try store.load(recordId: recordId))
        XCTAssertThrowsError(try store.verify(recordId: recordId, identity: nil))
    }

    func testOutOfBoundsRecordRejected() throws {
        let store = RecordsStore(root: tempRoot("bounds"), vault: Vault.ephemeralVault())
        var bad = sampleRecord()
        bad.xPx = 1920 // outside bounds
        XCTAssertThrowsError(try store.save(record: bad))
    }

    func testRecordsForFilter() throws {
        let store = RecordsStore(root: tempRoot("filter"), vault: Vault.ephemeralVault())
        _ = try store.save(record: sampleRecord())
        var other = sampleRecord()
        other.judgeId = "JUDGE-02"
        other.competitionId = "OTHER"
        _ = try store.save(record: other)
        let filtered = store.recordsFor(competitionId: "PJV-2026-R1",
                                        imageId: String(repeating: "a", count: 64))
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.judgeId, "JUDGE-01")
    }
}

final class AssessmentStoreTests: XCTestCase {

    private func tempRoot(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-tests-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSaveLoadRoundTripWithIntegrity() throws {
        let store = AssessmentStore(root: tempRoot("assessments"), vault: Vault.ephemeralVault())
        var a = try Assessment.create(assessmentId: "A-STORE-1", competitionId: "PJV-TEST-R1",
                                      imageId: String(repeating: "c", count: 64),
                                      tolerancePx: 12.0, now: "2026-11-21T10:00:00Z")
        try a.addJudgeSubmission(
            JudgeSubmission(judgeId: "JUDGE-01",
                            crosshair: Crosshair(xPx: 950, yPx: 512,
                                                 imageWidthPx: 1920, imageHeightPx: 1080),
                            submittedAt: "2026-11-21T10:00:00Z", note: ""),
            actor: "JUDGE-01", now: "2026-11-21T10:00:00Z")
        try store.save(assessment: a)
        let loaded = try store.load(assessmentId: "A-STORE-1")
        XCTAssertEqual(loaded.recomputedHash, a.recomputedHash)
        XCTAssertEqual(loaded.judges.count, 1)
    }

    /// Cross-language interop: the Python-produced sample assessment must load
    /// and verify in the Swift app (hash + audit chain recomputed by Swift).
    func testPythonSampleAssessmentVerifiesInSwift() throws {
        let data = try Fixtures.fixtureData("sample_assessment.json")
        let assessment = try JSONDecoder().decode(Assessment.self, from: data)
        XCTAssertEqual(assessment.assessmentId, "A-SAMPLE-001")
        XCTAssertEqual(assessment.tolerancePx, 12.0)
        XCTAssertEqual(assessment.judges.count, 4)
        XCTAssertEqual(assessment.consensus?.xPx, 513)
        XCTAssertEqual(assessment.consensus?.yPx, 342)
        XCTAssertEqual(assessment.consensus?.agreementRatio, 1.0)
        XCTAssertEqual(assessment.approval.status, "APPROVED")
        XCTAssertEqual(assessment.aiProposals.count, 1)
        try assessment.verifyIntegrity() // recomputed hash + chain, Swift-side
    }

    func testTamperedAssessmentRejectedOnLoad() throws {
        let store = AssessmentStore(root: tempRoot("tamper-a"), vault: Vault.ephemeralVault())
        var a = try Assessment.create(assessmentId: "A-TAMPER", competitionId: "PJV-TEST-R1",
                                      imageId: String(repeating: "d", count: 64),
                                      tolerancePx: 12.0, now: "2026-11-21T10:00:00Z")
        try a.addJudgeSubmission(
            JudgeSubmission(judgeId: "JUDGE-01",
                            crosshair: Crosshair(xPx: 100, yPx: 200,
                                                 imageWidthPx: 1000, imageHeightPx: 1000),
                            submittedAt: "2026-11-21T10:00:00Z", note: ""),
            actor: "JUDGE-01", now: "2026-11-21T10:00:00Z")
        try store.save(assessment: a)
        // mutate in memory so the stored hash no longer matches the content
        a.judges[0].crosshair.xPx = 999
        try store.save(assessment: a) // saves mutated record with OLD hash? No:
        // save() stores what it is given; the mutated struct still carries the
        // old assessmentHash, so load must fail integrity.
        XCTAssertThrowsError(try store.load(assessmentId: "A-TAMPER"))
    }
}
