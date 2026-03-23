import SwiftUI

struct AuthView: View {
    let supabaseClient: SupabaseClient
    var onAuthenticated: (() -> Void)?

    @State private var email = ""
    @State private var isSending = false
    @State private var linkSent = false
    @State private var errorMessage: String?
    @State private var canResend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In")
                .font(.title2.weight(.semibold))
            Text("Sign in to sync your data across devices and share with collaborators.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if linkSent {
                // Success state
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge")
                        .foregroundStyle(.green)
                    Text("Check your email and click the link to sign in.")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.1)))

                if canResend {
                    Button("Resend Magic Link") { sendLink() }
                }
            } else {
                // Input state
                HStack {
                    TextField("Email address", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendLink() }

                    Button("Send Magic Link") { sendLink() }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || isSending)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func sendLink() {
        guard !email.isEmpty else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await supabaseClient.sendMagicLink(email: email)
                linkSent = true
                canResend = false
                // Allow resend after 30 seconds
                try? await Task.sleep(for: .seconds(30))
                canResend = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
