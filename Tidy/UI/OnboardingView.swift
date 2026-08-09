import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedGoals: Set<TidyGoal>
    @State private var localOnlyAI: Bool

    init(selectedGoals: Set<TidyGoal>, localOnlyAI: Bool) {
        _selectedGoals = State(initialValue: selectedGoals.isEmpty ? [.writing, .clipboard] : selectedGoals)
        _localOnlyAI = State(initialValue: localOnlyAI)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text("Make Tidy yours")
                    .font(.system(size: 25, weight: .bold))
                Text("Choose what you want help with. You can change this later in Privacy settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(TidyGoal.allCases) { goal in
                    goalCard(goal)
                }
            }
            .padding(.horizontal, 28)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(localOnlyAI ? Color.green : Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep AI processing local")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Cloud and CLI AI providers will be blocked. Use Ollama or LanguageTool instead.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
                Toggle("", isOn: $localOnlyAI).labelsHidden()
            }
            .padding(14)
            .background(
                Color(NSColor.controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 28)
            .padding(.top, 16)

            Spacer(minLength: 18)

            HStack {
                Button("Use all features") {
                    selectedGoals = Set(TidyGoal.allCases)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Tidy has no analytics or advertising SDK.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))

                Button("Continue") {
                    appState.completeOnboarding(
                        goals: selectedGoals,
                        localOnlyAI: localOnlyAI
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedGoals.isEmpty)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .top) { Divider().opacity(0.5) }
        }
        .frame(width: 720, height: 630)
        .background(Color(NSColor.windowBackgroundColor))
        .interactiveDismissDisabled()
    }

    private func goalCard(_ goal: TidyGoal) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button {
            if isSelected {
                selectedGoals.remove(goal)
            } else {
                selectedGoals.insert(goal)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: goal.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        isSelected ? Color.accentColor : Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(NSColor.labelColor))
                    Text(goal.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.7) : Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
