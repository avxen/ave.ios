// PrivateJudgesWorkspaceApp.swift
// Private Judges Workspace - app entry point.
//
// First-launch authentication gates the entire UI (AuthGate).
// Tabs: Workspace / Judge / AI proposals / Records.
//
// IDENTITY NOTE: this is an independent judging application. It is not the
// official BOTB application, is not derived from it, and does not impersonate
// it. The internal project codename in documentation ("BOTB Private Judges
// Edition") refers to the fictional project persona in docs/PROJECT_PERSONA.md
// and is used for documentation only.

import SwiftUI

@main
struct PrivateJudgesWorkspaceApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AuthGate {
                MainTabView()
                    .environmentObject(appModel)
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Workspace", systemImage: "square.grid.2x2") }
            NavigationStack { JudgeFlowView() }
                .tabItem { Label("Judge", systemImage: "target") }
            NavigationStack { AIProposalView() }
                .tabItem { Label("AI", systemImage: "sparkles") }
            NavigationStack { RecordsView() }
                .tabItem { Label("Records", systemImage: "archivebox") }
        }
    }
}
