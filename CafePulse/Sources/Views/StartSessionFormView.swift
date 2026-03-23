import SwiftUI

struct StartSessionFormView: View {
    @Binding var draft: StartSessionDraft

    let suggestions: [String]
    let onStart: () -> Void
    let onCancel: () -> Void

    private var filteredSuggestions: [String] {
        guard !draft.normalizedCafeName.isEmpty else {
            return []
        }

        return suggestions
            .filter { $0.localizedCaseInsensitiveContains(draft.normalizedCafeName) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Session")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Cafe name", text: $draft.cafeName)
                    .textFieldStyle(.roundedBorder)

                if !filteredSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggestions")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                draft.cafeName = suggestion
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                TextField("Location (optional)", text: $draft.location)
                    .textFieldStyle(.roundedBorder)

                TextField("Tags (comma separated)", text: $draft.tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Start", action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.normalizedCafeName.isEmpty)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
