// JudgeFlowView.swift
// Private Judges Workspace - judge session: competition, judge identity,
// authorized image import, high-res viewer, native-resolution submission.
//
// AI proposals are NOT part of this flow. Every saved record is verified and
// carries competition_id + image_id (SHA-256 of raw bytes).

import SwiftUI
import PhotosUI
import UIKit

struct JudgeFlowView: View {
    @EnvironmentObject var app: AppModel
    var prefilledCompetitionId: String?
    var prefilledEntry: ImageEntry?

    @State private var competitionId = ""
    @State private var judgeId = ""
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var entry: ImageEntry?
    @State private var statusMessage: String?
    @State private var savedRecordId: String?
    @State private var showNewJudge = false
    @State private var newJudgeId = ""
    @State private var newJudgeName = ""

    var body: some View {
        Form {
            Section("Session") {
                Picker("Competition", selection: $competitionId) {
                    Text("-").tag("")
                    ForEach(app.workspace.competitions(), id: \.id) { c in
                        Text("\(c.id) — \(c.title)").tag(c.id)
                    }
                }
                Picker("Judge", selection: $judgeId) {
                    Text("-").tag("")
                    ForEach(app.workspace.judgeProfiles) { j in
                        Text("\(j.id) — \(j.displayName)").tag(j.id)
                    }
                }
                Button("Add judge profile") { showNewJudge = true }
            }
            Section("Image") {
                if prefilledEntry == nil {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Import assessment image", systemImage: "photo")
                    }
                }
                if let entry = entry {
                    EntryThumbnail(imageData: imageData)
                        .frame(maxHeight: 160)
                    Text("Native \(entry.widthPx)×\(entry.heightPx) px | source: \(entry.source)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("image_id \(entry.id.prefix(16))…")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    NavigationLink("Open viewer & place crosshair") {
                        viewer
                    }
                }
            }
            Section("Note") {
                TextField("Observation note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Status") {
                if let saved = savedRecordId {
                    Label("Saved record \(saved.prefix(16))…", systemImage: "checkmark.seal")
                        .font(.caption.monospaced()).foregroundStyle(.green)
                }
                if let msg = statusMessage {
                    Text(msg).font(.footnote).foregroundStyle(.red)
                }
                if !app.records.recordsFor(competitionId: competitionId,
                                           imageId: entry?.id ?? "").isEmpty {
                    let count = app.records.recordsFor(competitionId: competitionId,
                                                       imageId: entry?.id ?? "").count
                    Text("\(count) judge record(s) already exist for this image.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Judge")
        .onAppear {
            if let pre = prefilledCompetitionId { competitionId = pre }
            if let pre = prefilledEntry, entry == nil {
                entry = pre
                imageData = app.workspace.imageData(for: pre.id)
            }
        }
        .onChange(of: pickerItem) { newItem in
            guard let newItem = newItem else { return }
            Task { await importImage(from: newItem) }
        }
        .sheet(isPresented: $showNewJudge) {
            newJudgeSheet
        }
    }

    private var viewer: some View {
        ImageViewerView(
            imageData: imageData ?? Data(),
            widthPx: entry?.widthPx ?? 2,
            heightPx: entry?.heightPx ?? 2,
            consensusPoint: consensusPointForDisplay,
            otherJudges: otherJudgePoints,
            onSave: { point in
                saveRecord(point: point)
            })
    }

    private var newJudgeSheet: some View {
        NavigationStack {
            Form {
                TextField("Judge ID (e.g. JUDGE-01)", text: $newJudgeId)
                    .autocorrectionDisabled()
                TextField("Display name", text: $newJudgeName)
                Button("Create profile") {
                    do {
                        _ = try app.workspace.addJudgeProfile(id: newJudgeId,
                                                              displayName: newJudgeName)
                        app.log(action: "judge_profile_created",
                                details: ["judge_id": newJudgeId])
                        judgeId = newJudgeId
                        app.notify()
                        showNewJudge = false
                    } catch {
                        statusMessage = "Could not create judge: \(error)"
                    }
                }
                .disabled(newJudgeId.isEmpty || newJudgeName.isEmpty)
            }
            .navigationTitle("New judge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewJudge = false }
                }
            }
        }
    }

    // MARK: - data flow

    private func importImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            statusMessage = "Could not read the selected image."
            return
        }
        do {
            let imported = try app.workspace.addImageEntry(
                competitionId: competitionId,
                data: data,
                source: "photo_import",
                displayFilename: "imported image")
            app.log(action: "image_imported",
                    details: ["competition_id": competitionId,
                              "image_id": imported.id, "source": "photo_import"])
            app.notify()
            entry = imported
            imageData = data
            savedRecordId = nil
            statusMessage = nil
        } catch {
            statusMessage = "Import failed: \(error)"
        }
    }

    private var otherJudgePoints: [CoordinateEngine.PixelPoint] {
        app.records.recordsFor(competitionId: competitionId, imageId: entry?.id ?? "")
            .filter { $0.judgeId != judgeId }
            .map { CoordinateEngine.PixelPoint(x: $0.xPx, y: $0.yPx) }
    }

    private var consensusPointForDisplay: CoordinateEngine.PixelPoint? {
        guard let assessment = app.assessments.listAll().first(where: {
            $0.competitionId == competitionId && $0.imageId == entry?.id
        }), let c = assessment.consensus else { return nil }
        return CoordinateEngine.PixelPoint(x: c.xPx, y: c.yPx)
    }

    private func saveRecord(point: CoordinateEngine.PixelPoint) -> String {
        guard let entry = entry, !competitionId.isEmpty, !judgeId.isEmpty else {
            return "Select competition and judge first."
        }
        let record = CrosshairRecordFile(
            competitionId: competitionId,
            judgeId: judgeId,
            imageId: entry.id,
            imageWidthPx: entry.widthPx,
            imageHeightPx: entry.heightPx,
            xPx: point.x, yPx: point.y,
            note: note,
            createdAt: Timestamps.nowISO(),
            engineVersion: CoordinateEngine.engineVersion)
        do {
            let recordId = try app.records.save(record: record)
            app.log(action: "crosshair_record_saved",
                    details: ["record_id": recordId,
                              "competition_id": competitionId,
                              "judge_id": judgeId,
                              "image_id": entry.id])
            app.notify()
            savedRecordId = recordId
            return "Saved \(recordId.prefix(12))… (\(point.x), \(point.y)) px"
        } catch {
            return "Save failed: \(error)"
        }
    }
}

/// Small decrypted thumbnail for an image entry.
struct EntryThumbnail: View {
    let imageData: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            guard let imageData = imageData else { return }
            image = ImageToolkit.uiImage(from: imageData)
        }
    }
}
