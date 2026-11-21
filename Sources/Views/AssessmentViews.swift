// AssessmentViews.swift
// Private Judges Workspace - assessment assembly, multi-judge comparison,
// consensus display, AI proposal intake and human approval.

import SwiftUI
import CoreGraphics

/// Row used in lists: assessment summary with approval badge.
struct AssessmentRow: View {
    let assessment: Assessment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assessment.assessmentId).font(.headline)
            Text("image \(assessment.imageId.prefix(12))… | \(assessment.judges.count) judges | \(assessment.consensusMethod)")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            if let c = assessment.consensus {
                Text("consensus (\(c.xPx), \(c.yPx)) px | agreement \(String(format: "%.0f%%", c.agreementRatio * 100)) | spread \(String(format: "%.1f", c.maxSpreadPx)) px")
                    .font(.caption)
            } else {
                Text("no consensus (no judges)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: assessment.approval.status == "APPROVED"
                        ? "checkmark.seal.fill" : (assessment.approval.status == "REJECTED" ? "xmark.seal" : "hourglass"))
                Text(assessment.approval.status)
                Spacer()
                Image(systemName: assessment.auditChainValid ? "link" : "link.badge.plus")
                Text(assessment.auditChainValid ? "chain OK" : "chain BROKEN")
                    .foregroundStyle(assessment.auditChainValid ? .green : .red)
            }
            .font(.caption.bold())
            .foregroundStyle(assessment.approval.status == "APPROVED" ? .green : .orange)
        }
    }
}

/// Build an assessment from all saved judge records of one image.
struct AssessmentBuilderView: View {
    @EnvironmentObject var app: AppModel
    let competitionId: String
    let entry: ImageEntry

    @State private var toleranceText = "12"
    @State private var method = "geometric_median"
    @State private var statusMessage: String?
    @State private var createdId: String?

    private var records: [CrosshairRecordFile] {
        app.records.recordsFor(competitionId: competitionId, imageId: entry.id)
    }

    var body: some View {
        Form {
            Section("Source") {
                Text("image_id \(entry.id.prefix(16))… (\(entry.widthPx)×\(entry.heightPx) px)")
                    .font(.caption.monospaced())
                Text("\(records.count) judge record(s) for this image")
            }
            Section("Consensus settings") {
                TextField("Tolerance (px)", text: $toleranceText)
                    .keyboardType(.decimalPad)
                Picker("Method", selection: $method) {
                    Text("geometric_median").tag("geometric_median")
                    Text("per_axis_median").tag("per_axis_median")
                }
            }
            Section {
                Button("Build assessment") { build() }
                    .disabled(records.isEmpty || (Double(toleranceText) ?? -1) < 0)
                if records.isEmpty {
                    Text("No judge records for this image yet. Collect submissions in the Judge tab first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let msg = statusMessage {
                    Text(msg).font(.footnote).foregroundStyle(.red)
                }
                if let createdId = createdId {
                    NavigationLink("Open assessment \(createdId)") {
                        AssessmentDetailView(assessmentId: createdId)
                    }
                }
            }
            Section("Judge submissions (authoritative)") {
                ForEach(records, id: \.judgeId) { r in
                    Text("\(r.judgeId): (\(r.xPx), \(r.yPx)) px")
                        .font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("New assessment")
    }

    private func build() {
        let tolerance = Double(toleranceText) ?? -1
        guard tolerance >= 0 else { statusMessage = "Invalid tolerance."; return }
        let assessmentId = "A-" + Timestamps.nowISO()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        do {
            var assessment = try Assessment.create(
                assessmentId: assessmentId,
                competitionId: competitionId,
                imageId: entry.id,
                tolerancePx: tolerance,
                method: method)
            for r in records {
                try assessment.addJudgeSubmission(
                    JudgeSubmission(
                        judgeId: r.judgeId,
                        crosshair: Crosshair(xPx: r.xPx, yPx: r.yPx,
                                             imageWidthPx: r.imageWidthPx,
                                             imageHeightPx: r.imageHeightPx),
                        submittedAt: r.createdAt,
                        note: r.note),
                    actor: r.judgeId)
            }
            try app.assessments.save(assessment: assessment)
            app.log(action: "assessment_created",
                    details: ["assessment_id": assessmentId,
                              "competition_id": competitionId,
                              "image_id": entry.id,
                              "n_judges": String(records.count)])
            app.notify()
            createdId = assessmentId
            statusMessage = nil
        } catch {
            statusMessage = "Build failed: \(error)"
        }
    }
}

/// Full assessment detail: comparison, consensus, proposals, approval, audit.
struct AssessmentDetailView: View {
    @EnvironmentObject var app: AppModel
    let assessmentId: String

    @State private var assessment: Assessment?
    @State private var statusMessage: String?
    @State private var showManualProposal = false
    @State private var generatedProposals: [ProposalCandidate] = []
    @State private var proposalMessage: String?

    var body: some View {
        Group {
            if let assessment = assessment {
                detail(assessment)
            } else {
                Text("Assessment not found.").foregroundStyle(.secondary)
            }
        }
        .onAppear { reload() }
        .navigationTitle("Assessment")
    }

    @ViewBuilder
    private func detail(_ assessment: Assessment) -> some View {
        List {
            Section("Consensus (single coordinate engine)") {
                if let c = assessment.consensus {
                    Text("(\(c.xPx), \(c.yPx)) px · \(c.method)")
                        .font(.headline.monospaced())
                    Text("raw (\(String(format: "%.3f", c.rawX)), \(String(format: "%.3f", c.rawY))) · spread \(String(format: "%.2f", c.maxSpreadPx)) px · agreement \(String(format: "%.0f%%", c.agreementRatio * 100)) · tolerance \(String(format: "%.1f", c.tolerancePx)) px")
                        .font(.caption.monospaced())
                    Text("engine \(c.engineVersion)")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("No judges yet.").foregroundStyle(.secondary)
                }
            }
            Section("Judge submissions & distances") {
                ForEach(assessment.judges) { j in
                    judgeRow(assessment, j)
                }
            }
            Section("AI proposals — advisory only, never in consensus") {
                if assessment.aiProposals.isEmpty {
                    Text("None registered.").foregroundStyle(.secondary)
                }
                ForEach(assessment.aiProposals) { p in
                    VStack(alignment: .leading) {
                        Text("(\(p.xPx), \(p.yPx)) px · \(p.model)")
                            .font(.caption.monospaced())
                        Text("confidence \(String(format: "%.2f", p.confidence)) · id \(p.proposalId.prefix(12))…")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Button("Generate heuristic proposals") { generateProposals(assessment) }
                ForEach(generatedProposals) { cand in
                    Button {
                        registerProposal(assessment, candidate: cand)
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("register (\(cand.xPx), \(cand.yPx)) px · conf \(String(format: "%.2f", cand.confidence))")
                                .font(.caption.monospaced())
                        }
                    }
                }
                if let msg = proposalMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Button("Manual proposal entry") { showManualProposal = true }
                Text("Proposals are computer-generated or manually entered suggestions. They are stored in ai_proposals[] and never influence the consensus or the approval gate.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Human decision") {
                Button("Approve consensus (final decision)") {
                    decide(assessment, status: "APPROVED")
                }
                .disabled(assessment.consensus?.agreementRatio != 1.0)
                Button("Reject", role: .destructive) {
                    decide(assessment, status: "REJECTED")
                }
                Text("APPROVED requires agreement_ratio == 1.0 (all judges within tolerance).")
                    .font(.caption2).foregroundStyle(.secondary)
                if let approver = assessment.approval.approver,
                   let decided = assessment.approval.decidedAt {
                    Text("\(assessment.approval.status) by \(approver) at \(decided)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Audit history (hash-chained)") {
                HStack {
                    Text(assessment.auditChainValid ? "Chain VALID" : "Chain BROKEN")
                        .foregroundStyle(assessment.auditChainValid ? .green : .red)
                        .font(.caption.bold())
                    Spacer()
                    Text("\(assessment.audit.count) entries")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ForEach(assessment.audit) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.timestamp) | \(e.actor) | \(e.action)")
                            .font(.caption.monospaced())
                        Text("\(e.prevEntryHash == "GENESIS" ? "GENESIS" : String(e.prevEntryHash.prefix(10)) + "…") → " + String(e.entryHash.prefix(10)) + "…")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Button("Verify integrity") { verify(assessment) }
                if let msg = statusMessage {
                    Text(msg).font(.caption).foregroundStyle(statusMessage == "Integrity PASS" ? .green : .red)
                }
            }
        }
        .sheet(isPresented: $showManualProposal) {
            ManualProposalSheet(assessmentId: assessmentId)
        }
    }

    @ViewBuilder
    private func judgeRow(_ assessment: Assessment, _ j: JudgeSubmission) -> some View {
        HStack {
            Image(systemName: "target").foregroundStyle(.red)
            VStack(alignment: .leading) {
                Text(j.judgeId).font(.headline)
                Text("(\(j.crosshair.xPx), \(j.crosshair.yPx)) px  \(j.note)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let c = assessment.consensus {
                let distance = CoordinateEngine.euclideanDistancePx(
                    CoordinateEngine.PixelPoint(x: j.crosshair.xPx, y: j.crosshair.yPx),
                    CoordinateEngine.PixelPoint(x: c.xPx, y: c.yPx))
                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f px", distance))
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(distance <= c.tolerancePx ? .green : .orange)
                    Text(distance <= c.tolerancePx ? "within tolerance" : "outlier")
                        .font(.caption2)
                        .foregroundStyle(distance <= c.tolerancePx ? .green : .orange)
                }
            }
        }
    }

    private func reload() {
        assessment = try? app.assessments.load(assessmentId: assessmentId)
    }

    private func generateProposals(_ assessment: Assessment) {
        guard let data = app.workspace.imageData(for: assessment.imageId),
              let cgImage = ImageToolkit.cgImage(from: data) else {
            proposalMessage = "Source image not available for generation."
            return
        }
        generatedProposals = BallProposalEngine.proposals(cgImage: cgImage, maxProposals: 3)
        proposalMessage = generatedProposals.isEmpty
            ? "No blob candidates found (heuristic detector)."
            : "Tap a candidate to register it as an AI proposal."
    }

    private func registerProposal(_ assessment: Assessment, candidate: ProposalCandidate) {
        do {
            var updated = assessment
            try updated.addAIProposal(xPx: candidate.xPx, yPx: candidate.yPx,
                                      model: candidate.model, confidence: candidate.confidence,
                                      actor: "system")
            try app.assessments.save(assessment: updated)
            app.log(action: "ai_proposal_registered",
                    details: ["assessment_id": assessmentId,
                              "proposal_id": generatedProposals.first?.id ?? "-"])
            app.notify()
            reload()
            proposalMessage = "Proposal registered (separate from judge submissions)."
        } catch {
            proposalMessage = "Registration failed: \(error)"
        }
    }

    private func decide(_ assessment: Assessment, status: String) {
        do {
            var updated = assessment
            try updated.decide(status: status, approver: "project-owner")
            try app.assessments.save(assessment: updated)
            app.log(action: "assessment_\(status.lowercased())",
                    details: ["assessment_id": assessmentId, "approver": "project-owner"])
            app.notify()
            reload()
            statusMessage = nil
        } catch {
            statusMessage = "Decision failed: \(error)"
        }
    }

    private func verify(_ assessment: Assessment) {
        do {
            let loaded = try app.assessments.load(assessmentId: assessmentId)
            try loaded.verifyIntegrity()
            statusMessage = "Integrity PASS"
        } catch {
            statusMessage = "Integrity FAIL: \(error)"
        }
    }
}

struct ManualProposalSheet: View {
    @EnvironmentObject var app: AppModel
    let assessmentId: String
    @Environment(\.dismiss) private var dismiss
    @State private var xText = ""
    @State private var yText = ""
    @State private var model = "reference-proposal-v0"
    @State private var confidenceText = "0.80"
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Proposal (canonical pixel coordinates)") {
                    TextField("x_px", text: $xText).keyboardType(.numberPad)
                    TextField("y_px", text: $yText).keyboardType(.numberPad)
                    TextField("Model identifier", text: $model)
                    TextField("Confidence 0...1", text: $confidenceText)
                        .keyboardType(.decimalPad)
                }
                Section {
                    Button("Register AI proposal") { register() }
                        .disabled(!valid)
                    if let msg = statusMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Advisory only. Never counted as judge submissions; never changes the consensus.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manual proposal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var valid: Bool {
        guard let x = Int(xText), let y = Int(yText), x >= 0, y >= 0,
              let conf = Double(confidenceText), (0.0...1.0).contains(conf) else { return false }
        return !model.isEmpty
    }

    private func register() {
        do {
            var assessment = try app.assessments.load(assessmentId: assessmentId)
            try assessment.addAIProposal(xPx: Int(xText) ?? 0, yPx: Int(yText) ?? 0,
                                         model: model, confidence: Double(confidenceText) ?? 0,
                                         actor: "project-owner")
            try app.assessments.save(assessment: assessment)
            app.log(action: "ai_proposal_registered",
                    details: ["assessment_id": assessmentId, "source": "manual"])
            app.notify()
            dismiss()
        } catch {
            statusMessage = "Registration failed: \(error)"
        }
    }
}
