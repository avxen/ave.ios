// RecordsStore.swift
// Private Judges Workspace - persistent local records with integrity
// verification and at-rest encryption.
//
// Mirrors engine/crosshair_records.py:
//   - one file per record, filename = record_id (SHA-256 of canonical JSON)
//   - atomic writes (tmp + rename)
//   - verify() recomputes digests and identity consistency on every load
//   - on device, files are AES-GCM sealed (Vault); exports are unsealed
//     canonical JSON for cross-verification by the Python tools

import Foundation

struct CrosshairRecordFile: Codable, Equatable {
    var competitionId: String
    var judgeId: String
    var imageId: String
    var imageWidthPx: Int
    var imageHeightPx: Int
    var xPx: Int
    var yPx: Int
    var note: String
    var createdAt: String
    var engineVersion: String

    enum CodingKeys: String, CodingKey {
        case competitionId = "competition_id", judgeId = "judge_id"
        case imageId = "image_id"
        case imageWidthPx = "image_width_px"
        case imageHeightPx = "image_height_px"
        case xPx = "x_px", yPx = "y_px", note
        case createdAt = "created_at"
        case engineVersion = "engine_version"
    }

    /// Canonical payload (WITHOUT record_id) - mirrors CrosshairRecord.to_json_dict.
    var canonicalPayload: CanonicalValue {
        .object([
            ("competition_id", .string(competitionId)),
            ("judge_id", .string(judgeId)),
            ("image_id", .string(imageId)),
            ("image_width_px", .int(imageWidthPx)),
            ("image_height_px", .int(imageHeightPx)),
            ("x_px", .int(xPx)),
            ("y_px", .int(yPx)),
            ("note", .string(note)),
            ("created_at", .string(createdAt)),
            ("engine_version", .string(engineVersion)),
        ])
    }
}

enum VerificationStatus: String, Codable { case pass = "PASS", fail = "FAIL" }

struct VerificationReport: Codable {
    var recordId: String
    var status: VerificationStatus
    var checks: [String: VerificationStatus]

    enum CodingKeys: String, CodingKey {
        case recordId = "record_id", status, checks
    }
}

enum RecordStoreError: Error {
    case integrityFailure
    case invalidIdentifier
    case notFound
    case outsideBounds
    case vaultFailure
}

final class RecordsStore {
    let root: URL
    let vault: Vault

    init(root: URL? = nil, vault: Vault? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask)[0]
            .appendingPathComponent("PrivateJudgesWorkspace/Records", isDirectory: true)
        self.root = base
        self.vault = vault ?? (try? Vault.deviceVault()) ?? Vault.ephemeralVault()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func url(for recordId: String) throws -> URL {
        try CoordinateEngine.validateIdentifier(recordId)
        return root.appendingPathComponent(recordId + ".rec")
    }

    @discardableResult
    func save(record: CrosshairRecordFile) throws -> String {
        do {
            try CoordinateEngine.ImageIdentity(
                sha256: record.imageId,
                widthPx: record.imageWidthPx,
                heightPx: record.imageHeightPx
            ).validate(pointInside: CoordinateEngine.PixelPoint(x: record.xPx, y: record.yPx))
        } catch {
            throw RecordStoreError.outsideBounds
        }

        let recordId = CanonicalJSON.hash(record.canonicalPayload)
        let full: CanonicalValue = .object(
            payloadPairs(record) + [("record_id", .string(recordId))])
        let json = Data(CanonicalJSON.string(full).utf8)
        guard let sealed = try? vault.seal(json) else {
            throw RecordStoreError.vaultFailure
        }
        let target = try url(for: recordId)
        try sealed.write(to: target, options: .atomic)
        return recordId
    }

    private func payloadPairs(_ r: CrosshairRecordFile) -> [(String, CanonicalValue)] {
        [
            ("competition_id", .string(r.competitionId)),
            ("judge_id", .string(r.judgeId)),
            ("image_id", .string(r.imageId)),
            ("image_width_px", .int(r.imageWidthPx)),
            ("image_height_px", .int(r.imageHeightPx)),
            ("x_px", .int(r.xPx)),
            ("y_px", .int(r.yPx)),
            ("note", .string(r.note)),
            ("created_at", .string(r.createdAt)),
            ("engine_version", .string(r.engineVersion)),
        ]
    }

    private func parse(_ data: Data) throws -> (CrosshairRecordFile, String) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordId = dict["record_id"] as? String else {
            throw RecordStoreError.integrityFailure
        }
        let pairs: [(String, CanonicalValue)] = [
            ("competition_id", .string(dict["competition_id"] as? String ?? "")),
            ("judge_id", .string(dict["judge_id"] as? String ?? "")),
            ("image_id", .string(dict["image_id"] as? String ?? "")),
            ("image_width_px", .int(dict["image_width_px"] as? Int ?? 0)),
            ("image_height_px", .int(dict["image_height_px"] as? Int ?? 0)),
            ("x_px", .int(dict["x_px"] as? Int ?? 0)),
            ("y_px", .int(dict["y_px"] as? Int ?? 0)),
            ("note", .string(dict["note"] as? String ?? "")),
            ("created_at", .string(dict["created_at"] as? String ?? "")),
            ("engine_version", .string(dict["engine_version"] as? String ?? "")),
        ]
        let recomputed = CanonicalJSON.hash(.object(pairs))
        guard recomputed == recordId, dict["record_id"] as? String == recordId else {
            throw RecordStoreError.integrityFailure
        }
        let record = CrosshairRecordFile(
            competitionId: dict["competition_id"] as? String ?? "",
            judgeId: dict["judge_id"] as? String ?? "",
            imageId: dict["image_id"] as? String ?? "",
            imageWidthPx: dict["image_width_px"] as? Int ?? 0,
            imageHeightPx: dict["image_height_px"] as? Int ?? 0,
            xPx: dict["x_px"] as? Int ?? 0,
            yPx: dict["y_px"] as? Int ?? 0,
            note: dict["note"] as? String ?? "",
            createdAt: dict["created_at"] as? String ?? "",
            engineVersion: dict["engine_version"] as? String ?? "")
        return (record, recordId)
    }

    func load(recordId: String) throws -> CrosshairRecordFile {
        let fileUrl = try url(for: recordId)
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw RecordStoreError.notFound
        }
        let sealed = try Data(contentsOf: fileUrl)
        guard let plain = try? vault.open(sealed) else {
            throw RecordStoreError.integrityFailure
        }
        return try parse(plain).0
    }

    func verify(recordId: String, identity: CoordinateEngine.ImageIdentity?) throws
        -> VerificationReport {
        let fileUrl = try url(for: recordId)
        guard FileManager.default.fileExists(atPath: fileUrl.path),
              let sealed = try? Data(contentsOf: fileUrl),
              let plain = try? vault.open(sealed) else {
            throw RecordStoreError.notFound
        }
        var checks: [String: VerificationStatus] = [:]
        let (record, parsedId) = (try? parse(plain)) ?? (nil, "")
        checks["digest"] = (parsedId == recordId) ? .pass : .fail
        if let record = record {
            if let identity = identity {
                let ok = record.imageId == identity.sha256 &&
                    record.imageWidthPx == identity.widthPx &&
                    record.imageHeightPx == identity.heightPx
                checks["image_identity"] = ok ? .pass : .fail
            }
            checks["bounds"] = (record.xPx >= 0 && record.xPx < record.imageWidthPx &&
                                record.yPx >= 0 && record.yPx < record.imageHeightPx)
                ? .pass : .fail
        } else {
            checks["bounds"] = .fail
        }
        let status: VerificationStatus =
            checks.values.allSatisfy { $0 == .pass } ? .pass : .fail
        return VerificationReport(recordId: recordId, status: status, checks: checks)
    }

    func listRecordIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files.filter { $0.hasSuffix(".rec") }
            .map { String($0.dropLast(4)) }.sorted()
    }

    func recordsFor(competitionId: String, imageId: String) -> [CrosshairRecordFile] {
        listRecordIds().compactMap { try? load(recordId: $0) }
            .filter { $0.competitionId == competitionId && $0.imageId == imageId }
    }

    /// Unsealed canonical interchange JSON (with record_id) for exports.
    func exportJSON(recordId: String) throws -> Data {
        let record = try load(recordId: recordId)
        let full: CanonicalValue = .object(
            payloadPairs(record) + [("record_id", .string(recordId))])
        return Data(CanonicalJSON.string(full).utf8)
    }
}
