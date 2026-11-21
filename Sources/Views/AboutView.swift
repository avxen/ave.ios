// AboutView.swift
// Private Judges Workspace - project identity and honest scope statement.

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .frame(maxWidth: .infinity)
                    Text("Private Judges Workspace")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What this app is")
                                .font(.headline)
                            Text("An independent, private judging tool for crosshair-based image assessments with multi-judge consensus, human-approved final decisions, hash-chained audit trails and encrypted local storage.")
                            Text("It is NOT the official BOTB application and is not affiliated with, endorsed by, or derived from BOTB plc or the official BOTB app. It contains none of the original application's code or assets.")
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Project persona (fictional, documentation only)")
                                .font(.headline)
                            Text("James Alexander Bennett — Project owner. This persona is fictional and exists only inside project documents (reports, audit actor fields, sample artifacts). It does not correspond to a real individual.")
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Security model")
                                .font(.headline)
                            Text("• Access: PIN (salted PBKDF2 verifier in the Keychain) with optional device biometrics; exponential lockout.\n• Storage: AES-GCM encryption at rest with a 256-bit Keychain key.\n• Integrity: SHA-256 digests and hash-chained audit records, verified on every load.\n• AI separation: proposals are advisory, stored separately, never in the consensus.")
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Build info")
                                .font(.headline)
                            Text("engine \(CoordinateEngine.engineVersion) · app \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                                .font(.caption.monospaced())
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
