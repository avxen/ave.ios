// AIProposalView.swift
// Private Judges Workspace - AI proposal intake, STRICTLY SEPARATE from judge
// submissions. Proposals live in ai_proposals[] and never influence the
// consensus computation; the separation is enforced by the builder (judge ids
// beginning with "ai" are refused) and by the storage layout.

import SwiftUI
import CoreGraphics

struct AIProposalView: View {
    @EnvironmentObject var app: AppModel
    @State private var selectedAssessmentId = ""
    @State private var generated: [ProposalCandidate] = []
    @State private var statusMessage: String?

    private var assessments: [Assessment] {
        app.assessments.listAll()
    }

    var body: some View {
        Form {
            Section("Target assessment") {
                Picker("Assessment", selection: $selectedAssessmentId) {
                    Text("-").tag("")
                    ForEach(assessments) { a in
                        Text("\(a.assessmentId) (\(a.judges.count) judges)").tag(a.assessmentId)
                    }
                }
            }
            if !selectedAssessmentId.isEmpty {
                Section("Heuristic proposals (dark circular blob search)") {
                    Button("Generate proposals from image") { generate() }
                    ForEach(generated) { cand in
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text("(\(cand.xPx), \(cand.yPx)) px · \(cand.model)")
                                    .font(.caption.monospaced())
                                Text("confidence \(String(format: "%.2f", cand.confidence))")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Register") { register(candidate: cand) }
                                .buttonStyle(.bordered)
                        }
                    }
                    if let msg = statusMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Open assessment") {
                    NavigationLink("Open \(selectedAssessmentId)") {
                        AssessmentDetailView(assessmentId: selectedAssessmentId)
                    }
                }
            }
            Section("Separation rules") {
                Text("Proposals are advisory only. They are never counted as judge submissions and never change the consensus. Judge submissions always come from humans through the Judge tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI proposals")
        .onAppear { app.notify() }
    }

    private func generate() {
        guard let assessment = assessments.first(where: { $0.assessmentId == selectedAssessmentId }),
              let data = app.workspace.imageData(for: assessment.imageId),
              let cgImage = ImageToolkit.cgImage(from: data) else {
            statusMessage = "Source image not available."
            return
        }
        generated = BallProposalEngine.proposals(cgImage: cgImage, maxProposals: 3)
        statusMessage = generated.isEmpty
            ? "No blob candidates found. Use manual entry in the assessment detail."
            : "Tap Register to store a proposal in ai_proposals[]."
    }

    private func register(candidate: ProposalCandidate) {
        do {
            var assessment = try app.assessments.load(assessmentId: selectedAssessmentId)
            try assessment.addAIProposal(xPx: candidate.xPx, yPx: candidate.yPx,
                                         model: candidate.model,
                                         confidence: candidate.confidence,
                                         actor: "system")
            try app.assessments.save(assessment: assessment)
            app.log(action: "ai_proposal_registered",
                    details: ["assessment_id": selectedAssessmentId,
                              "proposal_id": candidate.id])
            app.notify()
            statusMessage = "Registered (separate from judge submissions)."
        } catch {
            statusMessage = "Registration failed: \(error)"
        }
    }
}
