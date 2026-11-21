// AssessmentBuilderTests.swift
// Assessment lifecycle parity with engine/multi_judge.py, pinned by vectors.

import XCTest
@testable import PrivateJudgesWorkspace

final class AssessmentBuilderTests: XCTestCase {

    private func fixtureAssessmentSpecs() throws -> [[String: JSONValue]] {
        let vectors = try Fixtures.referenceVectors()
        let cases = try XCTUnwrap(vectors["assessment_vectors"]?.arrayValue)
        return cases.compactMap { $0.objectValue }
    }

    private func rebuild(from spec: [String: JSONValue]) throws -> Assessment {
        let assessment = try XCTUnwrap(spec["assessment"]?.objectValue)
        let id = try XCTUnwrap(assessment["assessment_id"]?.stringValue)
        let competitionId = try XCTUnwrap(assessment["competition_id"]?.stringValue)
        let imageId = try XCTUnwrap(assessment["image_id"]?.stringValue)
        let tolerance = try XCTUnwrap(assessment["tolerance_px"]?.doubleValue)
        let method = try XCTUnwrap(assessment["consensus_method"]?.stringValue)
        let now = try XCTUnwrap(assessment["audit"]?.arrayValue?.first?.objectValue?["timestamp"]?.stringValue)

        var a = try Assessment.create(assessmentId: id, competitionId: competitionId,
                                      imageId: imageId, tolerancePx: tolerance,
                                      method: method, now: now)
        for judge in try XCTUnwrap(assessment["judges"]?.arrayValue) {
            let j = try XCTUnwrap(judge.objectValue)
            let ch = try XCTUnwrap(j["crosshair"]?.objectValue)
            try a.addJudgeSubmission(
                JudgeSubmission(
                    judgeId: try XCTUnwrap(j["judge_id"]?.stringValue),
                    crosshair: Crosshair(
                        xPx: try XCTUnwrap(ch["x_px"]?.intValue),
                        yPx: try XCTUnwrap(ch["y_px"]?.intValue),
                        imageWidthPx: try XCTUnwrap(ch["image_width_px"]?.intValue),
                        imageHeightPx: try XCTUnwrap(ch["image_height_px"]?.intValue)),
                    submittedAt: try XCTUnwrap(j["submitted_at"]?.stringValue),
                    note: try XCTUnwrap(j["note"]?.stringValue)),
                actor: try XCTUnwrap(j["judge_id"]?.stringValue),
                now: now)
        }
        for proposal in try XCTUnwrap(assessment["ai_proposals"]?.arrayValue) {
            let p = try XCTUnwrap(proposal.objectValue)
            try a.addAIProposal(xPx: try XCTUnwrap(p["x_px"]?.intValue),
                                yPx: try XCTUnwrap(p["y_px"]?.intValue),
                                model: try XCTUnwrap(p["model"]?.stringValue),
                                confidence: try XCTUnwrap(p["confidence"]?.doubleValue),
                                actor: "system", now: now)
        }
        if let approval = assessment["approval"]?.objectValue,
           approval["status"]?.stringValue == "APPROVED" || approval["status"]?.stringValue == "REJECTED" {
            try a.decide(status: try XCTUnwrap(approval["status"]?.stringValue),
                         approver: try XCTUnwrap(approval["approver"]?.stringValue),
                         now: try XCTUnwrap(approval["decided_at"]?.stringValue))
        }
        return a
    }

    /// The strongest parity test: rebuild Python assessments step-by-step and
    /// require byte-identical canonical serialization and hashes.
    func testRebuiltAssessmentsMatchPythonByteForByte() throws {
        for spec in try fixtureAssessmentSpecs() {
            let name = try XCTUnwrap(spec["name"]?.stringValue)
            let produced = try rebuild(from: spec)
            let expectedCanonical = try XCTUnwrap(spec["canonical_without_hash"]?.stringValue)
            let expectedHash = try XCTUnwrap(spec["assessment_hash"]?.stringValue)

            XCTAssertEqual(CanonicalJSON.string(produced.canonicalDict(includeHash: false)),
                           expectedCanonical, "canonical mismatch in \(name)")
            XCTAssertEqual(produced.recomputedHash, expectedHash,
                           "assessment hash mismatch in \(name)")
            XCTAssertTrue(produced.auditChainValid, "audit chain invalid in \(name)")
        }
    }

    // MARK: separation and gate rules (mirror multi_judge.py behaviour)

    private func makeAssessment() throws -> Assessment {
        try Assessment.create(assessmentId: "A-TEST-1", competitionId: "PJV-TEST-R1",
                              imageId: String(repeating: "b", count: 64),
                              tolerancePx: 12.0, now: "2026-11-21T10:00:00Z")
    }

    private func submission(judgeId: String, x: Int, y: Int) -> JudgeSubmission {
        JudgeSubmission(judgeId: judgeId,
                        crosshair: Crosshair(xPx: x, yPx: y,
                                             imageWidthPx: 1920, imageHeightPx: 1080),
                        submittedAt: "2026-11-21T10:00:00Z", note: "")
    }

    func testAIJudgeIdRefused() throws {
        var a = try makeAssessment()
        XCTAssertThrowsError(try a.addJudgeSubmission(submission(judgeId: "AI-1", x: 1, y: 1),
                                                       actor: "AI-1"))
        XCTAssertThrowsError(try a.addJudgeSubmission(submission(judgeId: "ai_helper", x: 1, y: 1),
                                                       actor: "ai_helper"))
    }

    func testDuplicateJudgeRefused() throws {
        var a = try makeAssessment()
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "JUDGE-01")
        XCTAssertThrowsError(try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 952, y: 513),
                                                      actor: "JUDGE-01"))
    }

    func testMixedImageSizesRefused() throws {
        var a = try makeAssessment()
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "JUDGE-01")
        var mixed = submission(judgeId: "JUDGE-02", x: 952, y: 513)
        mixed.crosshair.imageWidthPx = 1024
        mixed.crosshair.imageHeightPx = 768
        XCTAssertThrowsError(try a.addJudgeSubmission(mixed, actor: "JUDGE-02"))
    }

    func testApprovalGateRequiresUnanimity() throws {
        var a = try makeAssessment()
        // three judges, one clearly outside tolerance
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-02", x: 962, y: 520), actor: "J2")
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-03", x: 1500, y: 900), actor: "J3")
        let ratio = try XCTUnwrap(a.consensus?.agreementRatio)
        XCTAssertLessThan(ratio, 1.0)
        XCTAssertThrowsError(try a.decide(status: "APPROVED", approver: "project-owner"))
        XCTAssertNoThrow(try a.decide(status: "REJECTED", approver: "project-owner"))

        // unanimous set: APPROVED allowed
        var b = try makeAssessment()
        try b.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        try b.addJudgeSubmission(submission(judgeId: "JUDGE-02", x: 951, y: 512), actor: "J2")
        try b.addJudgeSubmission(submission(judgeId: "JUDGE-03", x: 949, y: 513), actor: "J3")
        XCTAssertEqual(b.consensus?.agreementRatio, 1.0)
        XCTAssertNoThrow(try b.decide(status: "APPROVED", approver: "project-owner"))
        XCTAssertEqual(b.approval.status, "APPROVED")
    }

    func testInvalidStatusRefused() throws {
        var a = try makeAssessment()
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        XCTAssertThrowsError(try a.decide(status: "MAYBE", approver: "project-owner"))
    }

    func testEmptyJudgesConsensusNil() throws {
        var a = try makeAssessment()
        XCTAssertNil(a.consensus)
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        XCTAssertNotNil(a.consensus)
    }

    func testAuditChainTamperDetection() throws {
        var a = try makeAssessment()
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-02", x: 962, y: 520), actor: "J2")
        XCTAssertTrue(a.auditChainValid)
        a.audit[1].action = "tampered"
        XCTAssertFalse(a.auditChainValid)
    }

    func testHashStabilityAcrossRebuild() throws {
        var a = try makeAssessment()
        try a.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        let hash1 = a.recomputedHash
        var b = try makeAssessment()
        try b.addJudgeSubmission(submission(judgeId: "JUDGE-01", x: 950, y: 512), actor: "J1")
        XCTAssertEqual(b.recomputedHash, hash1, "identical content must hash identically")
    }
}
