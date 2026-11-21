// AssessmentBuilder.swift
// Private Judges Workspace - assessment lifecycle mirroring engine/multi_judge.py.
//
// Separation rule (from the reference implementation): AI PROPOSALS ARE NOT
// JUDGE SUBMISSIONS. Judge ids beginning with "ai" are refused; proposals live
// in ai_proposals[] and are excluded from consensus.

import Foundation

enum RecordError: Error, Equatable {
    case invalidIdentifier
    case duplicateJudge(String)
    case mixedImageSizes
    case aiJudgeIdForbidden
    case invalidApprovalStatus
    case approvalRequiresUnanimity(currentRatio: Double)
    case noJudges
    case integrityFailure
    case notFound
}

extension Assessment {

    // MARK: creation

    /// Create an assessment. Mirrors Assessment.__post_init__: validates the
    /// competition id and appends the assessment_created audit entry.
    static func create(assessmentId: String, competitionId: String, imageId: String,
                       tolerancePx: Double, method: String = "geometric_median",
                       now: String = Timestamps.nowISO()) throws -> Assessment {
        try CoordinateEngine.validateIdentifier(competitionId)
        var a = Assessment(
            assessmentId: assessmentId,
            competitionId: competitionId,
            imageId: imageId,
            consensusMethod: method,
            tolerancePx: tolerancePx,
            judges: [],
            consensus: nil,
            approval: ApprovalRecord(status: "PENDING", approver: nil, decidedAt: nil),
            aiProposals: [],
            audit: [],
            engineVersion: CoordinateEngine.engineVersion,
            assessmentHash: "")
        a.appendAudit(actor: "system", action: "assessment_created",
                      details: ["assessment_id": assessmentId,
                                "competition_id": competitionId,
                                "image_id": imageId],
                      now: now)
        a.assessmentHash = a.recomputedHash
        return a
    }

    // MARK: judge submissions

    /// Append an individual judge submission; AI proposals are rejected.
    /// Mirrors add_judge_submission(): audit + silent consensus recompute.
    mutating func addJudgeSubmission(_ submission: JudgeSubmission, actor: String,
                                     now: String = Timestamps.nowISO()) throws {
        if submission.judgeId.lowercased().hasPrefix("ai") {
            throw RecordError.aiJudgeIdForbidden
        }
        try CoordinateEngine.validateIdentifier(submission.judgeId)
        if judges.contains(where: { $0.judgeId == submission.judgeId }) {
            throw RecordError.duplicateJudge(submission.judgeId)
        }
        if let first = judges.first,
           first.crosshair.imageWidthPx != submission.crosshair.imageWidthPx ||
           first.crosshair.imageHeightPx != submission.crosshair.imageHeightPx {
            throw RecordError.mixedImageSizes
        }
        judges.append(submission)
        appendAudit(actor: actor, action: "judge_submission_added",
                    details: ["judge_id": submission.judgeId], now: now)
        try recomputeConsensus()
        assessmentHash = recomputedHash
    }

    // MARK: consensus

    /// Mirrors recompute_consensus(silent=True): empty judges -> nil consensus.
    mutating func recomputeConsensus() throws {
        guard !judges.isEmpty else {
            consensus = nil
            return
        }
        let ref = judges[0].crosshair
        if judges.contains(where: {
            $0.crosshair.imageWidthPx != ref.imageWidthPx ||
            $0.crosshair.imageHeightPx != ref.imageHeightPx
        }) {
            throw RecordError.mixedImageSizes
        }
        let points = judges.map { CoordinateEngine.PixelPoint(x: $0.crosshair.xPx,
                                                              y: $0.crosshair.yPx) }
        let evaluation = try CoordinateEngine.evaluateConsensus(points, tolerancePx: tolerancePx,
                                                                method: consensusMethod)
        consensus = ConsensusInfo(evaluation: evaluation)
    }

    // MARK: AI proposals (separate from judges; never in consensus)

    mutating func addAIProposal(xPx: Int, yPx: Int, model: String, confidence: Double,
                                actor: String, now: String = Timestamps.nowISO()) throws {
        let proposal = AIProposal(xPx: xPx, yPx: yPx, model: model,
                                  confidence: confidence, proposalId: "")
        let proposalId = CanonicalJSON.hash(proposal.hashPayload)
        var accepted = proposal
        accepted.proposalId = proposalId
        aiProposals.append(accepted)
        appendAudit(actor: actor, action: "ai_proposal_registered",
                    details: ["proposal_id": proposalId], now: now)
        assessmentHash = recomputedHash
    }

    // MARK: human decision

    /// Mirrors decide(): APPROVED requires agreement_ratio == 1.0.
    mutating func decide(status: String, approver: String,
                         now: String = Timestamps.nowISO()) throws {
        guard status == "APPROVED" || status == "REJECTED" else {
            throw RecordError.invalidApprovalStatus
        }
        if status == "APPROVED" {
            let ratio = consensus?.agreementRatio ?? 0
            guard ratio >= 1.0 else {
                throw RecordError.approvalRequiresUnanimity(currentRatio: ratio)
            }
        }
        approval = ApprovalRecord(status: status, approver: approver, decidedAt: now)
        appendAudit(actor: approver, action: "approval_\(status.lowercased())",
                    details: ["approver": approver], now: now)
        assessmentHash = recomputedHash
    }

    // MARK: audit plumbing

    mutating func appendAudit(actor: String, action: String,
                              details: [String: String], now: String) {
        let prev = audit.last?.entryHash ?? "GENESIS"
        let entry = AuditEntry(timestamp: now, actor: actor, action: action,
                               details: details, prevEntryHash: prev, entryHash: "")
        let hash = CanonicalJSON.hash(entry.hashPayload)
        var complete = entry
        complete.entryHash = hash
        audit.append(complete)
    }

    /// Integrity check used on every load (mirrors from_json_dict hash check).
    func verifyIntegrity() throws {
        guard assessmentHash == recomputedHash else {
            throw RecordError.integrityFailure
        }
        guard auditChainValid else {
            throw RecordError.integrityFailure
        }
    }
}
