// AuditLog.swift
// Private Judges Workspace - app-level hash-chained audit trail (JSONL-style
// entries, AES-GCM sealed at rest). Mirrors the audit chain rules of
// engine/multi_judge.py: GENESIS link, entry hash = SHA-256 of the canonical
// payload without entry_hash.

import Foundation

final class WorkspaceAuditLog {
    private(set) var entries: [AuditEntry] = []
    let root: URL
    let vault: Vault

    init(root: URL? = nil, vault: Vault? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                    in: .userDomainMask)[0]
            .appendingPathComponent("PrivateJudgesWorkspace", isDirectory: true)
        self.root = base
        self.vault = vault ?? (try? Vault.deviceVault()) ?? Vault.ephemeralVault()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    private var fileURL: URL { root.appendingPathComponent("audit.enc") }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let sealed = try? Data(contentsOf: fileURL),
              let plain = try? vault.open(sealed),
              let decoded = try? JSONDecoder().decode([AuditEntry].self, from: plain) else {
            return
        }
        entries = decoded
    }

    func save() throws {
        guard let plain = try? JSONEncoder().encode(entries),
              let sealed = try? vault.seal(plain) else {
            throw RecordStoreError.vaultFailure
        }
        try sealed.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func append(actor: String, action: String, details: [String: String],
                now: String = Timestamps.nowISO()) -> AuditEntry {
        let prev = entries.last?.entryHash ?? "GENESIS"
        var entry = AuditEntry(timestamp: now, actor: actor, action: action,
                               details: details, prevEntryHash: prev, entryHash: "")
        entry.entryHash = CanonicalJSON.hash(entry.hashPayload)
        entries.append(entry)
        try? save()
        return entry
    }

    func verifyChain() -> Bool {
        var prev = "GENESIS"
        for entry in entries {
            guard entry.prevEntryHash == prev,
                  CanonicalJSON.hash(entry.hashPayload) == entry.entryHash else { return false }
            prev = entry.entryHash
        }
        return true
    }

    /// Canonical JSONL export (one entry per line), unsealed.
    func exportJSONL() -> Data {
        let lines = entries.map { CanonicalJSON.string($0.canonicalDict) }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
