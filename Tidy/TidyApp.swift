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
        WindowGroup("Tidy") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 540)
                .preferredColorScheme(resolvedColorScheme)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Tidy", systemImage: "sparkles") {
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

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Tidy", systemImage: "power")
            }
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
