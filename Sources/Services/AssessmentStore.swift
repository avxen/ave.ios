// AssessmentStore.swift
// Private Judges Workspace - encrypted persistence for assessment records,
// with integrity verification on every load (mirrors Assessment.from_json_dict
// hash verification).

import Foundation

final class AssessmentStore {
    let root: URL
    let vault: Vault

    init(root: URL? = nil, vault: Vault? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask)[0]
            .appendingPathComponent("PrivateJudgesWorkspace/Assessments", isDirectory: true)
        self.root = base
        self.vault = vault ?? (try? Vault.deviceVault()) ?? Vault.ephemeralVault()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func url(for assessmentId: String) -> URL {
        root.appendingPathComponent(assessmentId + ".aenc")
    }

    func save(assessment: Assessment) throws {
        let plain = try JSONEncoder().encode(assessment)
        guard let sealed = try? vault.seal(plain) else {
            throw RecordStoreError.vaultFailure
        }
        try sealed.write(to: url(for: assessment.assessmentId), options: .atomic)
    }

    func load(assessmentId: String) throws -> Assessment {
        let target = url(for: assessmentId)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw RecordStoreError.notFound
        }
        let sealed = try Data(contentsOf: target)
        guard let plain = try? vault.open(sealed) else {
            throw RecordStoreError.integrityFailure
        }
        let assessment = try JSONDecoder().decode(Assessment.self, from: plain)
        try assessment.verifyIntegrity()
        return assessment
    }

    func listAssessmentIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return files.filter { $0.hasSuffix(".aenc") }
            .map { String($0.dropLast(5)) }.sorted()
    }

    func listAll() -> [Assessment] {
        listAssessmentIds().compactMap { try? load(assessmentId: $0) }
    }

    /// Canonical interchange JSON (with assessment_hash) for exports.
    func exportJSON(assessment: Assessment) -> Data {
        Data(CanonicalJSON.string(assessment.canonicalDict()).utf8)
    }
}
