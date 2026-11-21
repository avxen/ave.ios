// ExportView.swift
// Private Judges Workspace - export and backup of judging records.

import SwiftUI

struct ExportView: View {
    @EnvironmentObject var app: AppModel
    @State private var includeImages = false
    @State private var exportDirectory: URL?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Workspace export") {
                Toggle("Include image files", isOn: $includeImages)
                Button("Export & share (Files / AirDrop / iCloud)") {
                    export()
                }
                if let msg = statusMessage {
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
                Text("The export contains canonical JSON files byte-compatible with the Python reference tools (engine/), a records CSV, the hash-chained audit log as JSONL, and manifest.json + SHA256SUMS.txt with a SHA-256 digest for every file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What is exported") {
                Text("competitions.json · judges.json · judges.csv · records/*.json · assessments/*.json · audit_log.jsonl \(includeImages ? "· images/*.jpg" : "") · manifest.json · SHA256SUMS.txt")
                    .font(.caption.monospaced())
            }
            Section("Integrity") {
                let counts = app.stats
                Text("\(counts.records) judge records and \(counts.assessments) assessments will be exported with their stored digests so any recipient can re-verify them.")
                    .font(.caption)
            }
        }
        .navigationTitle("Export & backup")
        .sheet(isPresented: $showShare) {
            if !shareItems.isEmpty {
                ActivityView(items: shareItems)
            }
        }
    }

    private func export() {
        do {
            let result = try ExportService.exportWorkspace(
                workspace: app.workspace,
                records: app.records,
                assessments: app.assessments,
                audit: app.audit,
                includeImages: includeImages)
            app.log(action: "workspace_exported",
                    details: ["file_count": String(result.fileCount),
                              "include_images": includeImages ? "1" : "0"])
            exportDirectory = result.directory
            shareItems = [result.directory]
            showShare = true
            statusMessage = "Exported \(result.fileCount) files to a shareable folder."
        } catch {
            statusMessage = "Export failed: \(error)"
        }
    }
}
