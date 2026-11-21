// AssessmentModels.swift
// Private Judges Workspace - record formats mirroring schemas/assessment.schema.json
// and engine/multi_judge.py. Individual judge submissions are authoritative;
// AI proposals are stored separately and never enter the judges array.
//
// Hash compatibility: every dict serialized for hashing uses CanonicalJSON,
// which is byte-identical to the Python reference canonical serialization.

import Foundation

// MARK: - Basic record types

struct Crosshair: Codable, Equatable {
    var xPx: Int
    var yPx: Int
    var imageWidthPx: Int
    var imageHeightPx: Int

    enum CodingKeys: String, CodingKey {
        case xPx = "x_px", yPx = "y_px"
        case imageWidthPx = "image_width_px"
        case imageHeightPx = "image_height_px"
    }

    var canonicalDict: CanonicalValue {
        .object([
            ("x_px", .int(xPx)), ("y_px", .int(yPx)),
            ("image_width_px", .int(imageWidthPx)),
            ("image_height_px", .int(imageHeightPx)),
        ])
    }
}

struct JudgeSubmission: Codable, Equatable, Identifiable {
    var judgeId: String
    var crosshair: Crosshair
    var submittedAt: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case judgeId = "judge_id", crosshair
        case submittedAt = "submitted_at", note
    }
    var id: String { judgeId }

    var canonicalDict: CanonicalValue {
        .object([
            ("judge_id", .string(judgeId)),
            ("crosshair", crosshair.canonicalDict),
            ("submitted_at", .string(submittedAt)),
            ("note", .string(note)),
        ])
    }
}

struct ApprovalRecord: Codable, Equatable {
    var status: String   // PENDING | APPROVED | REJECTED
    var approver: String?
    var decidedAt: String?

    enum CodingKeys: String, CodingKey {
        case status, approver
        case decidedAt = "decided_at"
    }

    var canonicalDict: CanonicalValue {
        .object([
            ("status", .string(status)),
            ("approver", approver.map { CanonicalValue.string($0) } ?? .null),
            ("decided_at", decidedAt.map { CanonicalValue.string($0) } ?? .null),
        ])
    }
}

struct AuditEntry: Codable, Equatable, Identifiable {
    var timestamp: String
    var actor: String
    var action: String
    var details: [String: String]
    var prevEntryHash: String
    var entryHash: String

    enum CodingKeys: String, CodingKey {
        case timestamp, actor, action, details
        case prevEntryHash = "prev_entry_hash"
        case entryHash = "entry_hash"
    }
    var id: String { entryHash }

    /// Hash payload = entry WITHOUT entry_hash (mirrors multi_judge._audit_entry).
    var hashPayload: CanonicalValue {
        .object([
            ("timestamp", .string(timestamp)),
            ("actor", .string(actor)),
            ("action", .string(action)),
            ("details", .object(details.sorted { $0.key < $1.key }
                .map { ($0.key, CanonicalValue.string($0.value)) })),
            ("prev_entry_hash", .string(prevEntryHash)),
        ])
    }

    var canonicalDict: CanonicalValue {
        .object([
            ("timestamp", .string(timestamp)),
            ("actor", .string(actor)),
            ("action", .string(action)),
            ("details", .object(details.sorted { $0.key < $1.key }
                .map { ($0.key, CanonicalValue.string($0.value)) })),
            ("prev_entry_hash", .string(prevEntryHash)),
            ("entry_hash", .string(entryHash)),
        ])
    }
}

struct AIProposal: Codable, Equatable, Identifiable {
    var xPx: Int
    var yPx: Int
    var model: String
    var confidence: Double
    var proposalId: String

    enum CodingKeys: String, CodingKey {
        case xPx = "x_px", yPx = "y_px", model, confidence
        case proposalId = "proposal_id"
    }
    var id: String { proposalId }

    /// Proposal hash payload WITHOUT proposal_id (mirrors add_ai_proposal).
    var hashPayload: CanonicalValue {
        .object([
            ("x_px", .int(xPx)), ("y_px", .int(yPx)),
            ("model", .string(model)), ("confidence", .double(confidence)),
        ])
    }

    var canonicalDict: CanonicalValue {
        .object([
            ("x_px", .int(xPx)), ("y_px", .int(yPx)),
            ("model", .string(model)), ("confidence", .double(confidence)),
            ("proposal_id", .string(proposalId)),
        ])
    }
}

struct ConsensusInfo: Codable, Equatable {
    var method: String
    var xPx: Int
    var yPx: Int
    var rawX: Double
    var rawY: Double
    var engineVersion: String
    var tolerancePx: Double
    var maxSpreadPx: Double
    var agreementRatio: Double
    var nJudges: Int

    enum CodingKeys: String, CodingKey {
        case method
        case xPx = "x_px", yPx = "y_px"
        case rawX = "raw_x", rawY = "raw_y"
        case engineVersion = "engine_version"
        case tolerancePx = "tolerance_px"
        case maxSpreadPx = "max_spread_px"
        case agreementRatio = "agreement_ratio"
        case nJudges = "n_judges"
    }

    init(evaluation: CoordinateEngine.ConsensusEvaluation) {
        method = evaluation.method
        xPx = evaluation.xPx
        yPx = evaluation.yPx
        rawX = evaluation.rawX
        rawY = evaluation.rawY
        engineVersion = CoordinateEngine.engineVersion
        tolerancePx = evaluation.tolerancePx
        maxSpreadPx = evaluation.maxSpreadPx
        agreementRatio = evaluation.agreementRatio
        nJudges = evaluation.nJudges
    }

    var canonicalDict: CanonicalValue {
        .object([
            ("method", .string(method)),
            ("x_px", .int(xPx)), ("y_px", .int(yPx)),
            ("raw_x", .double(rawX)), ("raw_y", .double(rawY)),
            ("engine_version", .string(engineVersion)),
            ("tolerance_px", .double(tolerancePx)),
            ("max_spread_px", .double(maxSpreadPx)),
            ("agreement_ratio", .double(agreementRatio)),
            ("n_judges", .int(nJudges)),
        ])
    }
}

// MARK: - Full assessment record

/// Full multi-judge assessment record (JSON interchangeable with the Python
/// reference implementation, including the assessment_hash integrity digest).
struct Assessment: Codable, Identifiable {
    var assessmentId: String
    var competitionId: String
    var imageId: String
    var consensusMethod: String
    var tolerancePx: Double
    var judges: [JudgeSubmission]
    var consensus: ConsensusInfo?
    var approval: ApprovalRecord
    var aiProposals: [AIProposal]
    var audit: [AuditEntry]
    var engineVersion: String
    var assessmentHash: String

    enum CodingKeys: String, CodingKey {
        case assessmentId = "assessment_id"
        case competitionId = "competition_id"
        case imageId = "image_id"
        case consensusMethod = "consensus_method"
        case tolerancePx = "tolerance_px"
        case judges, consensus, approval
        case aiProposals = "ai_proposals"
        case audit
        case engineVersion = "engine_version"
        case assessmentHash = "assessment_hash"
    }
    var id: String { assessmentId }

    /// Canonical dict over the whole record; mirrors Assessment.to_json_dict.
    /// When includeHash is false the assessment_hash key is omitted (that is
    /// exactly the payload whose SHA-256 becomes the assessment hash).
    func canonicalDict(includeHash: Bool = true) -> CanonicalValue {
        var pairs: [(String, CanonicalValue)] = [
            ("assessment_id", .string(assessmentId)),
            ("competition_id", .string(competitionId)),
            ("image_id", .string(imageId)),
            ("consensus_method", .string(consensusMethod)),
            ("tolerance_px", .double(tolerancePx)),
            ("judges", .array(judges.map { $0.canonicalDict })),
            ("consensus", consensus.map { $0.canonicalDict } ?? .null),
            ("approval", approval.canonicalDict),
            ("ai_proposals", .array(aiProposals.map { $0.canonicalDict })),
            ("audit", .array(audit.map { $0.canonicalDict })),
            ("engine_version", .string(engineVersion)),
        ]
        if includeHash { pairs.append(("assessment_hash", .string(assessmentHash))) }
        return .object(pairs)
    }

    /// SHA-256 over the canonical serialization excluding assessment_hash.
    var recomputedHash: String {
        CanonicalJSON.hash(canonicalDict(includeHash: false))
    }

    /// Mirrors Assessment.audit_chain_valid().
    var auditChainValid: Bool {
        var prev = "GENESIS"
        for entry in audit {
            guard entry.prevEntryHash == prev,
                  CanonicalJSON.hash(entry.hashPayload) == entry.entryHash else { return false }
            prev = entry.entryHash
        }
        return true
    }
}

// MARK: - Timestamps

enum Timestamps {
    /// UTC ISO-8601 with second precision, e.g. 2026-11-21T10:00:00Z
    /// (matches engine/crosshair_records.utc_now_iso format).
    static func nowISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
