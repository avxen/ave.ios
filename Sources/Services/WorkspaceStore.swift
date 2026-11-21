// WorkspaceStore.swift
// Private Judges Workspace - competitions, image entries, judge profiles and
// image blobs, all AES-GCM sealed at rest. Image identity is ALWAYS the
// SHA-256 of the raw bytes (never a filename).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Competition: Codable, Identifiable, Equatable {
    var id: String              // validated identifier ^[A-Za-z0-9._-]{1,128}$
    var title: String           // free text display title
    var createdAtISO: String
    var status: String          // active | archived
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAtISO = "created_at"
        case status, notes
    }
}

struct ImageEntry: Codable, Identifiable, Equatable {
    var id: String              // image_id = SHA-256 of raw bytes
    var competitionId: String
    var widthPx: Int
    var heightPx: Int
    var importedAtISO: String
    var source: String          // photo_import | video_frame
    var sourceVideoId: String?  // SHA-256 of source video bytes when video_frame
    var frameSeconds: Double?   // timestamp in the source video
    var displayFilename: String

    enum CodingKeys: String, CodingKey {
        case id
        case competitionId = "competition_id"
        case widthPx = "width_px"
        case heightPx = "height_px"
        case importedAtISO = "imported_at"
        case source
        case sourceVideoId = "source_video_id"
        case frameSeconds = "frame_seconds"
        case displayFilename = "display_filename"
    }
}

struct JudgeProfile: Codable, Identifiable, Equatable {
    var id: String              // validated identifier
    var displayName: String
    var createdAtISO: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAtISO = "created_at"
    }
}

struct WorkspaceData: Codable, Equatable {
    var competitions: [Competition] = []
    var imageEntries: [ImageEntry] = []
    var judgeProfiles: [JudgeProfile] = []
}

enum WorkspaceError: Error {
    case duplicateIdentifier
    case notFound
    case invalidIdentifier
    case invalidImage
    case storageFailure
}

final class WorkspaceStore {
    private(set) var data: WorkspaceData = WorkspaceData()
    let root: URL
    let vault: Vault

    init(root: URL? = nil, vault: Vault? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask)[0]
            .appendingPathComponent("PrivateJudgesWorkspace/Workspace", isDirectory: true)
        self.root = base
        self.vault = vault ?? (try? Vault.deviceVault()) ?? Vault.ephemeralVault()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: base.appendingPathComponent("Images", isDirectory: true),
            withIntermediateDirectories: true)
        load()
    }

    // MARK: - persistence

    private var documentURL: URL { root.appendingPathComponent("workspace.enc") }

    private func load() {
        guard FileManager.default.fileExists(atPath: documentURL.path),
              let sealed = try? Data(contentsOf: documentURL),
              let plain = try? vault.open(sealed),
              let decoded = try? JSONDecoder().decode(WorkspaceData.self, from: plain) else {
            return
        }
        data = decoded
    }

    private func persist() throws {
        guard let plain = try? JSONEncoder().encode(data),
              let sealed = try? vault.seal(plain) else {
            throw WorkspaceError.storageFailure
        }
        try sealed.write(to: documentURL, options: .atomic)
    }

    // MARK: - competitions

    @discardableResult
    func addCompetition(id: String, title: String, notes: String = "",
                        now: String = Timestamps.nowISO()) throws -> Competition {
        try CoordinateEngine.validateIdentifier(id)
        guard !data.competitions.contains(where: { $0.id == id }) else {
            throw WorkspaceError.duplicateIdentifier
        }
        let competition = Competition(id: id, title: title,
                                      createdAtISO: now, status: "active", notes: notes)
        data.competitions.append(competition)
        try persist()
        return competition
    }

    func setStatus(competitionId: String, status: String) throws {
        guard let index = data.competitions.firstIndex(where: { $0.id == competitionId }) else {
            throw WorkspaceError.notFound
        }
        data.competitions[index].status = status
        try persist()
    }

    func competitions(activeOnly: Bool = true) -> [Competition] {
        data.competitions
            .filter { !activeOnly || $0.status == "active" }
            .sorted { $0.createdAtISO > $1.createdAtISO }
    }

    // MARK: - image entries and blobs

    /// Import authorized image data (PhotosPicker / file importer). Computes
    /// the image identity from the raw bytes and stores the blob sealed.
    @discardableResult
    func addImageEntry(competitionId: String, data imageData: Data,
                       source: String, sourceVideoId: String? = nil,
                       frameSeconds: Double? = nil,
                       displayFilename: String = "image",
                       now: String = Timestamps.nowISO()) throws -> ImageEntry {
        guard data.competitions.contains(where: { $0.id == competitionId }) else {
            throw WorkspaceError.notFound
        }
        guard let source_ = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source_) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source_, 0, nil) else {
            throw WorkspaceError.invalidImage
        }
        let imageId = CoordinateEngine.imageSHA256(imageData)
        let entry = ImageEntry(id: imageId, competitionId: competitionId,
                               widthPx: cgImage.width, heightPx: cgImage.height,
                               importedAtISO: now, source: source,
                               sourceVideoId: sourceVideoId,
                               frameSeconds: frameSeconds,
                               displayFilename: displayFilename)
        if !data.imageEntries.contains(where: { $0.id == imageId && $0.competitionId == competitionId }) {
            data.imageEntries.append(entry)
        }
        let blobURL = root.appendingPathComponent("Images/\(imageId).enc")
        if !FileManager.default.fileExists(atPath: blobURL.path),
           let sealed = try? vault.seal(imageData) {
            try sealed.write(to: blobURL, options: .atomic)
        }
        try persist()
        return entry
    }

    func entries(competitionId: String) -> [ImageEntry] {
        data.imageEntries
            .filter { $0.competitionId == competitionId }
            .sorted { $0.importedAtISO < $1.importedAtISO }
    }

    func entry(imageId: String, competitionId: String) -> ImageEntry? {
        data.imageEntries.first { $0.id == imageId && $0.competitionId == competitionId }
    }

    func imageData(for imageId: String) -> Data? {
        let blobURL = root.appendingPathComponent("Images/\(imageId).enc")
        guard let sealed = try? Data(contentsOf: blobURL) else { return nil }
        return try? vault.open(sealed)
    }

    // MARK: - judges

    @discardableResult
    func addJudgeProfile(id: String, displayName: String,
                         now: String = Timestamps.nowISO()) throws -> JudgeProfile {
        try CoordinateEngine.validateIdentifier(id)
        guard !data.judgeProfiles.contains(where: { $0.id == id }) else {
            throw WorkspaceError.duplicateIdentifier
        }
        let judge = JudgeProfile(id: id, displayName: displayName, createdAtISO: now)
        data.judgeProfiles.append(judge)
        try persist()
        return judge
    }

    var judgeProfiles: [JudgeProfile] {
        data.judgeProfiles.sorted { $0.id < $1.id }
    }
}
