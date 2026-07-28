import SwiftUI

struct TerminalView: View {
    @EnvironmentObject private var terminalService: TerminalService
    @Binding var isSidebarCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.45)
            terminalContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            terminalService.startIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(isSidebarCollapsed ? "Show sidebar (⌘/)" : "Hide sidebar (⌘/)")
            .accessibilityLabel(isSidebarCollapsed ? "Show sidebar" : "Hide sidebar")

            Divider()
                .frame(height: 22)

            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(terminalService.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(terminalService.currentDirectory)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                terminalService.chooseWorkingDirectory()
            } label: {
                Label("Working Directory", systemImage: "folder")
            }
            .help("Choose working directory and restart the terminal")

            Button {
                terminalService.restart()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .help("Restart terminal session")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: statusColor.opacity(0.45), radius: 3)
            .help(statusText)
    }

    private var statusColor: Color {
        if terminalService.errorMessage != nil || !terminalService.isRendererHealthy {
            return .red
        }
        return terminalService.isProcessRunning ? .green : .orange
    }

    private var statusText: String {
        if let error = terminalService.errorMessage {
            return error
        }
        if !terminalService.isRendererHealthy {
            return "Renderer error"
        }
        return terminalService.isProcessRunning ? "Shell running" : "Shell exited"
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let surfaceView = terminalService.surfaceView {
            GhosttySurfaceRepresentable(surfaceView: surfaceView)
                .background(.black)
                .contentShape(Rectangle())
                .onTapGesture {
                    terminalService.focus()
                }
        } else if let error = terminalService.errorMessage {
            ContentUnavailableView {
                Label("Terminal Unavailable", systemImage: "terminal")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    terminalService.restart()
                }
            }
        } else {
            ProgressView("Starting terminal…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    let surfaceView: GhosttyTerminalSurfaceView

    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        surfaceView
    }

    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}
