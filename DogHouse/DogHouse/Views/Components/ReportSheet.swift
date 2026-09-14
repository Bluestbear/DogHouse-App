//
//  ReportSheet.swift
//  DogHouse
//
//  Reason picker + optional details for reporting a sending, a person or a
//  photo. Offers to block the person too, since that is what most people
//  actually want when they report.
//

import SwiftUI

struct ReportSheet: View {
    let target: ReportTarget
    /// Shown as a "Block" toggle when set; nil for content you can't block
    /// the author of (your own partner's photo, say).
    var blockableUser: (id: String, name: String)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var moderation = ModerationService.shared
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What's wrong?")
                }

                Section("Details (optional)") {
                    TextField("Tell us more", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let blockableUser {
                    Section {
                        Toggle(isOn: $alsoBlock) {
                            Label("Also block \(blockableUser.name)", systemImage: "hand.raised.fill")
                        }
                    } footer: {
                        Text("Blocking hides everything from \(blockableUser.name) and removes the couple friendship. They aren't told.")
                    }
                }

                if let errorText {
                    Text(errorText).font(.dhCaption).foregroundStyle(.red)
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                    }
                }
            }
            .alert("Thanks for the report", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("We'll look at it within 24 hours.")
            }
        }
    }

    private func send() async {
        isSending = true
        errorText = nil
        defer { isSending = false }
        do {
            try await moderation.report(target, reason: reason, details: details)
            if alsoBlock, let blockableUser {
                try await moderation.block(userId: blockableUser.id)
            }
            HapticService.shared.success()
            sent = true
        } catch {
            errorText = error.localizedDescription
            HapticService.shared.error()
        }
    }
}
