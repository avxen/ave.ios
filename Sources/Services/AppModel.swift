// AppModel.swift
// Private Judges Workspace - shared application model.

import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let workspace: WorkspaceStore
    let records: RecordsStore
    let assessments: AssessmentStore
    let audit: WorkspaceAuditLog

    init(vault: Vault? = nil) {
        let deviceVault = vault ?? (try? Vault.deviceVault())
        workspace = WorkspaceStore(vault: deviceVault)
        records = RecordsStore(vault: deviceVault)
        assessments = AssessmentStore(vault: deviceVault)
        audit = WorkspaceAuditLog(vault: deviceVault)
    }

    /// Trigger UI refresh after direct store mutations.
    func notify() {
        objectWillChange.send()
    }

    func log(action: String, details: [String: String], actor: String = "project-owner") {
        audit.append(actor: actor, action: action, details: details)
    }

    var stats: (competitions: Int, images: Int, records: Int, assessments: Int) {
        (workspace.competitions(activeOnly: false).count,
         workspace.data.imageEntries.count,
         records.listRecordIds().count,
         assessments.listAssessmentIds().count)
    }
}

// MARK: - Share sheet wrapper

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - helpers

extension Double {
    func clampedTo(_ range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clampedTo(_ range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

enum ImageToolkit {
    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func uiImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
}
