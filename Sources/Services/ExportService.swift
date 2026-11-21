// ExportService.swift
// Private Judges Workspace - export and backup of judging records.
//
// Exports are explicit user actions. Every file is written in the canonical
// interchange format byte-compatible with the Python reference tools, and a
// SHA256SUMS.txt + manifest.json (with per-file SHA-256) is produced.

import Foundation

enum ExportService {

    struct ExportResult {
        let directory: URL
        let fileCount: Int
    }

    /// Full workspace export: competitions, judges, records, assessments,
    /// app audit log, images and a manifest with SHA-256 digests.
    static func exportWorkspace(workspace: WorkspaceStore,
                                records: RecordsStore,
                                assessments: AssessmentStore,
                                audit: WorkspaceAuditLog,
                                includeImages: Bool) throws -> ExportResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-export-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [(relativePath: String, data: Data)] = []

        // competitions + judges (canonical)
        let competitions = workspace.competitions(activeOnly: false)
        let compDict = CanonicalValue.object([
            ("competitions", .array(competitions.map { c in
                CanonicalValue.object([
                    ("id", .string(c.id)), ("title", .string(c.title)),
                    ("created_at", .string(c.createdAtISO)),
                    ("status", .string(c.status)), ("notes", .string(c.notes)),
                ])
            })),
        ])
        files.append(("competitions.json", Data(CanonicalJSON.string(compDict).utf8)))

        let judgesDict = CanonicalValue.object([
            ("judges", .array(workspace.judgeProfiles.map { j in
                CanonicalValue.object([
                    ("id", .string(j.id)), ("display_name", .string(j.displayName)),
                    ("created_at", .string(j.createdAtISO)),
                ])
            })),
        ])
        files.append(("judges.json", Data(CanonicalJSON.string(judgesDict).utf8)))

        files.append(("judges.csv", judgesCSV(workspace: workspace)))

        // crosshair records (canonical, one file per record)
        let recordIds = records.listRecordIds()
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("records", isDirectory: true),
            withIntermediateDirectories: true)
        for recordId in recordIds {
            if let data = try? records.exportJSON(recordId: recordId) {
                files.append(("records/\(recordId).json", data))
            }
        }

        // assessments (canonical, one file per assessment)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("assessments", isDirectory: true),
            withIntermediateDirectories: true)
        for assessment in assessments.listAll() {
            files.append(("assessments/\(assessment.assessmentId).json",
                          assessments.exportJSON(assessment: assessment)))
        }

        // app audit log (canonical JSONL)
        files.append(("audit_log.jsonl", audit.exportJSONL()))

        // images (unsealed original bytes)
        if includeImages {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("images", isDirectory: true),
                withIntermediateDirectories: true)
            for entry in workspace.data.imageEntries {
                if let blob = workspace.imageData(for: entry.id) {
                    files.append(("images/\(entry.id).jpg", blob))
                }
            }
        }

        // write files + manifest + SHA256SUMS
        for file in files {
            let target = dir.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: target, options: .atomic)
        }

        var sums = ""
        var manifestFiles: [CanonicalValue] = []
        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            let digest = CoordinateEngine.sha256Hex(file.data)
            sums += "\(digest)  \(file.relativePath)\n"
            manifestFiles.append(.object([
                ("path", .string(file.relativePath)),
                ("sha256", .string(digest)),
                ("bytes", .int(file.data.count)),
            ]))
        }
        let sumsData = Data(sums.utf8)
        try sumsData.write(to: dir.appendingPathComponent("SHA256SUMS.txt"), options: .atomic)

        let manifest: CanonicalValue = .object([
            ("app", .string("Private Judges Workspace")),
            ("app_version", .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")),
            ("engine_version", .string(CoordinateEngine.engineVersion)),
            ("exported_at", .string(Timestamps.nowISO())),
            ("file_count", .int(files.count)),
            ("files", .array(manifestFiles)),
        ])
        try Data(CanonicalJSON.string(manifest).utf8)
            .write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)

        return ExportResult(directory: dir, fileCount: files.count + 2)
    }

    static func judgesCSV(workspace: WorkspaceStore) -> Data {
        var lines = ["judge_id,display_name,created_at"]
        for j in workspace.judgeProfiles {
            lines.append("\(csvField(j.id)),\(csvField(j.displayName)),\(csvField(j.createdAtISO))")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Crosshair records CSV (one row per record).
    static func recordsCSV(records: RecordsStore) throws -> Data {
        var lines = ["competition_id,judge_id,image_id,x_px,y_px,image_width_px,image_height_px,created_at,note"]
        for recordId in records.listRecordIds() {
            guard let r = try? records.load(recordId: recordId) else { continue }
            lines.append([
                csvField(r.competitionId), csvField(r.judgeId), csvField(r.imageId),
                String(r.xPx), String(r.yPx),
                String(r.imageWidthPx), String(r.imageHeightPx),
                csvField(r.createdAt), csvField(r.note),
            ].joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
