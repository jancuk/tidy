import SwiftUI

enum WorkspaceDesign {
    static let canvas = Color("TodayCanvas")
    static let surface = Color("TodaySurface")
    static let inset = Color("TodayInset")
    static let border = Color("TodayBorder")
}

struct WorkspaceSearchField: View {
    @Binding var text: String
    let placeholder: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).accessibilityLabel(label)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
        }.font(.system(size: 13)).padding(11)
            .frame(maxWidth: 330).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WorkspaceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 10 : 14)
            .padding(.vertical, controlSize == .small || controlSize == .mini ? 6 : 9)
            .foregroundStyle(prominent ? WorkspaceDesign.canvas : configuration.role == .destructive ? Color.red : Color.primary)
            .background(prominent ? (configuration.role == .destructive ? Color.red : Color.primary) : WorkspaceDesign.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : WorkspaceDesign.border))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
            .contentShape(Capsule())
    }
}

struct WorkspaceHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }.buttonStyle(WorkspaceButtonStyle())
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .background(WorkspaceDesign.canvas)
        .overlay(alignment: .bottom) { WorkspaceDesign.border.frame(height: 1) }
    }
}

struct WorkspaceEmptyState: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 66, height: 66).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 26, design: .serif))
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
}

struct TodayWritingField: View {
    @Binding var text: String
    var placeholder: String
    var label: String
    var height: CGFloat = 180
    var monospaced = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.top, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .accessibilityLabel(label)
        }
        .font(.system(size: 15, design: monospaced ? .monospaced : .default))
        .lineSpacing(6)
        .padding(14).frame(height: height)
        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Color.accentColor.opacity(0.55) : WorkspaceDesign.border))
    }
}
