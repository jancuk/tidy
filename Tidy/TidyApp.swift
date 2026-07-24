//
//  TidyApp.swift
//  Tidy
//
//  Created by Azhar Amir on 17/05/26.
//

import AppKit
import SwiftUI

@main
struct TidyApp: App {
    @StateObject private var appState = AppState()
    @AppStorage(AppDefaults.appearanceMode) private var appearanceMode = "system"

    var body: some Scene {
        WindowGroup("Tidy", id: "main") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 1220, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Tidy", systemImage: "sparkles") {
            TidyMenuBarView(appState: appState, jiraService: appState.jiraService)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.correctionLogStore)
                .environmentObject(appState.clipboardService)
                .preferredColorScheme(resolvedColorScheme)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

private struct TidyMenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var jiraService: JiraService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            appState.openAskAI()
        } label: {
            Label("Ask AI Anything", systemImage: "text.bubble")
        }

        Button {
            appState.openPalette()
        } label: {
            Label("Open Clipboard Palette", systemImage: "doc.on.clipboard")
        }

        Button {
            appState.tidyClipboardText()
        } label: {
            Label("Tidy Clipboard Text", systemImage: "textformat")
        }

        Menu {
            Button {
                openWindow(id: "main")
                appState.openJiraNotifications()
            } label: {
                Label("Open Notification Center", systemImage: "bell")
            }

            Button {
                Task { await appState.refreshJira() }
            } label: {
                Label("Refresh Jira", systemImage: "arrow.clockwise")
            }

            if !jiraService.notifications.isEmpty {
                Divider()
                ForEach(Array(jiraService.notifications.prefix(7))) { notification in
                    Button {
                        jiraService.markNotificationRead(notification)
                        openWindow(id: "main")
                        appState.openJira(issueID: notification.issueID)
                    } label: {
                        Label(
                            "\(notification.issueKey) · \(notification.detail) · \(notification.priority)",
                            systemImage: jiraService.unreadNotificationIDs.contains(notification.id)
                                ? "circle.fill"
                                : "circle"
                        )
                    }
                }
            }
        } label: {
            Label(
                jiraService.unreadCount == 0
                    ? "Jira Notifications"
                    : "Jira Notifications (\(jiraService.unreadCount))",
                systemImage: jiraService.unreadCount == 0 ? "bell" : "bell.badge.fill"
            )
        }

        Button {
            openWindow(id: "main")
            appState.openJira()
        } label: {
            Label("Open Jira Workspace", systemImage: "shippingbox")
        }

        Divider()

        Button(role: .destructive) {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Tidy", systemImage: "power")
        }
    }
}
