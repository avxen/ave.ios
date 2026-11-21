// RecordsView.swift
// Private Judges Workspace - history, verification and app-level audit trail.

import SwiftUI

struct RecordsView: View {
    @EnvironmentObject var app: AppModel
    @State private var section = "Assessments"
    @State private var verifyReport: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                Text("Assessments").tag("Assessments")
                Text("Records").tag("Records")
                Text("Audit log").tag("Audit log")
                Text("Archived").tag("Archived")
            }
            .pickerStyle(.segmented)
            .padding()

            switch section {
            case "Assessments": assessmentList
            case "Records": recordList
            case "Audit log": auditList
            default: archivedList
            }
        }
        .navigationTitle("Records & history")
        .onAppear { app.notify() }
    }

    private var assessmentList: some View {
        List {
            ForEach(app.assessments.listAll()) { a in
                NavigationLink {
                    AssessmentDetailView(assessmentId: a.assessmentId)
                } label: {
                    AssessmentRow(assessment: a)
                }
            }
            if app.assessments.listAll().isEmpty {
                Text("No assessments yet.").foregroundStyle(.secondary)
            }
        }
    }

    private var recordList: some View {
        List {
            Section {
                Button("Verify all records") {
                    verifyAll()
                }
                if let report = verifyReport {
                    Text(report).font(.caption.monospaced())
                }
            }
            Section("Judge records") {
                ForEach(app.records.listRecordIds(), id: \.self) { recordId in
                    if let r = try? app.records.load(recordId: recordId) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.competitionId) · \(r.judgeId)")
                                .font(.subheadline.monospaced())
                            Text("(\(r.xPx), \(r.yPx)) px of \(r.imageWidthPx)×\(r.imageHeightPx) · \(r.createdAt)")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if !r.note.isEmpty {
                                Text(r.note).font(.caption)
                            }
                        }
                    }
                }
                if app.records.listRecordIds().isEmpty {
                    Text("No records saved yet.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var auditList: some View {
        List {
            Section {
                HStack {
                    Text(app.audit.verifyChain() ? "App audit chain VALID" : "App audit chain BROKEN")
                        .foregroundStyle(app.audit.verifyChain() ? .green : .red)
                        .font(.caption.bold())
                    Spacer()
                    Text("\(app.audit.entries.count) entries")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(app.audit.entries.enumerated().reversed()), id: \.element.id) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.timestamp) | \(e.actor) | \(e.action)").font(.caption.monospaced())
                    if !e.details.isEmpty {
                        Text(e.details.map { "\($0.key)=\($0.value.prefix(20))" }.sorted().joined(separator: "  "))
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var archivedList: some View {
        List {
            ForEach(app.workspace.competitions(activeOnly: false)
                .filter { $0.status == "archived" }) { c in
                VStack(alignment: .leading) {
                    Text("\(c.id) — \(c.title)")
                    Text("archived · \(app.workspace.entries(competitionId: c.id).count) images")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if app.workspace.competitions(activeOnly: false)
                .filter({ $0.status == "archived" }).isEmpty {
                Text("No archived competitions.").foregroundStyle(.secondary)
            }
        }
    }

    private func verifyAll() {
        var pass = 0, fail = 0
        for recordId in app.records.listRecordIds() {
            if let report = try? app.records.verify(recordId: recordId, identity: nil),
               report.status == .pass {
                pass += 1
            } else {
                fail += 1
            }
        }
        verifyReport = "verify: \(pass) PASS, \(fail) FAIL of \(pass + fail)"
    }
}
