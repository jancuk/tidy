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
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        WindowGroup("Tidy") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Tidy", systemImage: "sparkles") {
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

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }

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
        }
    }
}
