// CompetitionViews.swift
// Private Judges Workspace - home screen, competition management and
// authorized import (photo + video-frame analysis).

import SwiftUI
import PhotosUI
import AVFoundation
import CoreGraphics

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var showNewCompetition = false
    @State private var newId = ""
    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var showAbout = false

    var body: some View {
        List {
            Section("Competitions") {
                ForEach(app.workspace.competitions()) { c in
                    NavigationLink {
                        CompetitionDetailView(competitionId: c.id)
                    } label: {
                        HStack {
                            Image(systemName: c.status == "active" ? "flask" : "archivebox")
                                .foregroundStyle(c.status == "active" ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(c.title.isEmpty ? c.id : c.title)
                                Text("\(c.id) · \(app.workspace.entries(competitionId: c.id).count) image(s)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    showNewCompetition = true
                } label: {
                    Label("New competition", systemImage: "plus")
                }
            }
            Section("Judges") {
                ForEach(app.workspace.judgeProfiles) { j in
                    Text("\(j.id) — \(j.displayName)")
                }
                if app.workspace.judgeProfiles.isEmpty {
                    Text("No judge profiles yet. Add one in the Judge tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Workspace") {
                let stats = app.stats
                Text("\(stats.competitions) competitions · \(stats.images) images · \(stats.records) judge records · \(stats.assessments) assessments")
                    .font(.caption.monospaced())
                HStack {
                    Text("Audit chain")
                    Spacer()
                    Text(app.audit.verifyChain() ? "VALID" : "BROKEN")
                        .font(.caption.bold())
                        .foregroundStyle(app.audit.verifyChain() ? .green : .red)
                }
                NavigationLink("Export & backup") { ExportView() }
                Button("About & project identity") { showAbout = true }
            }
        }
        .navigationTitle("Judges Workspace")
        .onAppear { app.notify() }
        .sheet(isPresented: $showNewCompetition) { newCompetitionSheet }
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    private var newCompetitionSheet: some View {
        NavigationStack {
            Form {
                TextField("Competition ID (e.g. PJV-2026-R1)", text: $newId)
                    .autocorrectionDisabled()
                TextField("Title", text: $newTitle)
                TextField("Notes", text: $newNotes, axis: .vertical)
                Button("Create") {
                    do {
                        _ = try app.workspace.addCompetition(id: newId, title: newTitle,
                                                             notes: newNotes)
                        app.log(action: "competition_created", details: ["competition_id": newId])
                        app.notify()
                        newId = ""; newTitle = ""; newNotes = ""
                        showNewCompetition = false
                    } catch {
                        app.notify()
                    }
                }
                .disabled(newId.isEmpty)
            }
            .navigationTitle("New competition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewCompetition = false }
                }
            }
        }
    }
}

struct CompetitionDetailView: View {
    @EnvironmentObject var app: AppModel
    let competitionId: String

    @State private var pickerItem: PhotosPickerItem?
    @State private var showVideoSheet = false
    @State private var statusMessage: String?

    private var competition: Competition? {
        app.workspace.competitions(activeOnly: false).first { $0.id == competitionId }
    }

    var body: some View {
        List {
            Section("Image entries") {
                ForEach(app.workspace.entries(competitionId: competitionId)) { entry in
                    NavigationLink {
                        JudgeFlowView(prefilledCompetitionId: competitionId,
                                      prefilledEntry: entry)
                    } label: {
                        HStack {
                            EntryThumbnail(imageData: app.workspace.imageData(for: entry.id))
                                .frame(width: 64, height: 44)
                                .clipped()
                            VStack(alignment: .leading) {
                                Text("\(entry.widthPx)×\(entry.heightPx) px")
                                    .font(.subheadline.monospaced())
                                Text("\(entry.source)\(entry.frameSeconds.map { String(format: " @ %.1fs", $0) } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("image_id \(entry.id.prefix(12))…")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if app.workspace.entries(competitionId: competitionId).isEmpty {
                    Text("No images imported yet.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Authorized import") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Import photo", systemImage: "photo")
                }
                Button {
                    showVideoSheet = true
                } label: {
                    Label("Import video frame", systemImage: "video")
                }
            }
            Section("Assessments") {
                ForEach(app.assessments.listAll()
                    .filter { $0.competitionId == competitionId }) { a in
                    NavigationLink {
                        AssessmentDetailView(assessmentId: a.assessmentId)
                    } label: {
                        AssessmentRow(assessment: a)
                    }
                }
                if app.assessments.listAll()
                    .filter({ $0.competitionId == competitionId }).isEmpty {
                    Text("No assessments yet. Open an image and build one from judge records.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Competition") {
                if let c = competition {
                    Text("\(c.status) · created \(c.createdAtISO)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if !c.notes.isEmpty {
                        Text(c.notes).font(.caption)
                    }
                    Button(c.status == "active" ? "Archive competition" : "Restore competition") {
                        try? app.workspace.setStatus(
                            competitionId: competitionId,
                            status: c.status == "active" ? "archived" : "active")
                        app.log(action: "competition_status_changed",
                                details: ["competition_id": competitionId,
                                          "status": c.status == "active" ? "archived" : "active"])
                        app.notify()
                    }
                }
            }
            if let msg = statusMessage {
                Section { Text(msg).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle(competitionId)
        .sheet(isPresented: $showVideoSheet) {
            VideoFrameSheet(competitionId: competitionId)
        }
        .onChange(of: pickerItem) { newItem in
            guard let newItem = newItem else { return }
            Task { await importPhoto(from: newItem) }
        }
    }

    private func importPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            statusMessage = "Could not read the selected image."
            return
        }
        do {
            let entry = try app.workspace.addImageEntry(competitionId: competitionId,
                                                        data: data,
                                                        source: "photo_import")
            app.log(action: "image_imported",
                    details: ["competition_id": competitionId,
                              "image_id": entry.id, "source": "photo_import"])
            app.notify()
            statusMessage = nil
        } catch {
            statusMessage = "Import failed: \(error)"
        }
    }
}

/// Video-frame import sheet: pick a video, scrub to a frame, capture it as an
/// authorized image entry with recorded source metadata.
struct VideoFrameSheet: View {
    @EnvironmentObject var app: AppModel
    let competitionId: String
    @Environment(\.dismiss) private var dismiss

    @State private var videoItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var videoInfo: VideoFrameExtractor.VideoInfo?
    @State private var frameSeconds = 0.0
    @State private var frameImage: CGImage?
    @State private var frameData: Data?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Source video") {
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("Choose video", systemImage: "video")
                    }
                    if let info = videoInfo {
                        Text("duration \(String(format: "%.1f", info.durationSeconds)) s | video_id \(info.sourceVideoId.prefix(12))…")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if videoURL != nil {
                    Section("Frame") {
                        if frameSeconds > 0 {
                            Slider(value: $frameSeconds,
                                   in: 0...max(0.1, videoInfo?.durationSeconds ?? 1))
                            Text(String(format: "t = %.2f s", frameSeconds))
                                .font(.caption.monospaced())
                        }
                        Button("Load frame at \(String(format: "%.2f", frameSeconds)) s") {
                            Task { await captureFrame() }
                        }
                        if let cgImage = frameImage {
                            Image(uiImage: UIImage(cgImage: cgImage))
                                .resizable().scaledToFit()
                                .frame(maxHeight: 220)
                        }
                    }
                    Section {
                        Button("Save frame as image entry") {
                            saveFrame()
                        }
                        .disabled(frameData == nil)
                    }
                }
                if let msg = statusMessage {
                    Section { Text(msg).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Video frame")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: videoItem) { item in
                guard let item = item else { return }
                Task { await loadVideo(from: item) }
            }
        }
    }

    private func loadVideo(from item: PhotosPickerItem) async {
        guard let video = try? await item.loadTransferable(type: LoadedVideo.self) else {
            statusMessage = "Could not read the selected video."
            return
        }
        do {
            let info = try await VideoFrameExtractor.videoInfo(url: video.url)
            videoInfo = info
            videoURL = video.url
            frameSeconds = 0
            frameImage = nil
            frameData = nil
        } catch {
            statusMessage = "Video load failed: \(error)"
        }
    }

    private func captureFrame() async {
        guard let url = videoURL else { return }
        do {
            let cgImage = try await VideoFrameExtractor.extractFrame(url: url,
                                                                     atSeconds: frameSeconds)
            frameImage = cgImage
            frameData = VideoFrameExtractor.frameData(from: cgImage)
        } catch {
            statusMessage = "Frame extraction failed: \(error)"
        }
    }

    private func saveFrame() {
        guard let data = frameData, let info = videoInfo else { return }
        do {
            let entry = try app.workspace.addImageEntry(
                competitionId: competitionId,
                data: data,
                source: "video_frame",
                sourceVideoId: info.sourceVideoId,
                frameSeconds: frameSeconds,
                displayFilename: "video frame")
            app.log(action: "video_frame_imported",
                    details: ["competition_id": competitionId,
                              "image_id": entry.id,
                              "source_video_id": info.sourceVideoId,
                              "frame_seconds": String(format: "%.2f", frameSeconds)])
            app.notify()
            dismiss()
        } catch {
            statusMessage = "Save failed: \(error)"
        }
    }
}
