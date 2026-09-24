//
//  InputView.swift
//  DogHouse
//
//  Feedback form, pushed from the Input section at the bottom of Profile.
//  Users send complaints or feature suggestions. Each
//  submission is written to the `feedback` collection; the
//  onFeedbackCreated Cloud Function emails it to the developer.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct InputView: View {
    @EnvironmentObject var authService: AuthService

    @State private var kind: FeedbackKind = .suggestion
    @State private var message = ""
    @State private var isSending = false
    @State private var showSent = false
    @State private var errorText: String?

    enum FeedbackKind: String, CaseIterable, Identifiable {
        case suggestion = "Suggestion"
        case complaint = "Complaint"
        var id: String { rawValue }
        var emoji: String { self == .suggestion ? "💡" : "🐛" }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(FeedbackKind.allCases) { k in
                        Text("\(k.emoji) \(k.rawValue)").tag(k)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("What's on your mind?")
            } footer: {
                Text(kind == .suggestion
                     ? "Got an idea for a feature? I'd love to hear it!"
                     : "Something not working or bugging you? Tell me and I'll fix it.")
            }

            Section("Your message") {
                TextEditor(text: $message)
                    .frame(minHeight: 140)
            }

            if let errorText {
                Section {
                    Text(errorText).font(.dhCaption).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send to Harrison 📬")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(trimmedMessage.isEmpty || isSending)
            } footer: {
                Text("Your message and display name are sent straight to the developer.")
            }
        }
        .navigationTitle("Input")
        .dhPageBackground()
        .alert("Thanks! 🐾", isPresented: $showSent) {
            Button("You're welcome") {}
        } message: {
            Text("Your \(kind.rawValue.lowercased()) is on its way. Every message gets read!")
        }
    }

    private func submit() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let text = trimmedMessage
        guard !text.isEmpty else { return }
        isSending = true
        errorText = nil
        Task {
            defer { isSending = false }
            do {
                try await FirebaseService.shared.db.collection("feedback").document().setData([
                    "fromUserId": uid,
                    "fromName": authService.userProfile?.displayName ?? "Unknown",
                    "type": kind.rawValue.lowercased(),
                    "text": String(text.prefix(2000)),
                    "createdAt": Timestamp(date: Date())
                ])
                message = ""
                showSent = true
                HapticService.shared.success()
            } catch {
                errorText = "Couldn't send: \(error.localizedDescription)"
                HapticService.shared.error()
            }
        }
    }
}

#Preview {
    NavigationStack { InputView() }
        .environmentObject(AuthService())
}
