//
//  SendToDoghouseSheet.swift
//  DogHouse
//

import SwiftUI

struct SendToDoghouseSheet: View {
    @ObservedObject var doghouseService: DoghouseService
    var partnerName: String = "them"
    var onSent: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var suggestion = ""
    @State private var isPublic = false
    @State private var isSending = false
    @State private var showError = false
    @State private var errorText = ""

    private let reasonChips = [
        "Forgot something important", "Left a mess", "Said something rude",
        "Didn't listen", "Was on their phone too much", "Broke a promise"
    ]
    private let suggestionChips = [
        "Make breakfast in bed", "Pick up flowers on the way home",
        "Do the laundry", "Cook their favorite meal",
        "Wash dishes for 3 days", "Walk the dog for a week"
    ]

    private var bg: Color { Color(red: 0.98, green: 0.95, blue: 0.90) }
    private var headerColor: Color { Color(red: 0.52, green: 0.38, blue: 0.22) }
    private var sendColor: Color { Color(red: 0.86, green: 0.33, blue: 0.33) }

    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Close button row
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(headerColor)
                                .padding(10)
                                .background(Color(red: 0.89, green: 0.81, blue: 0.70))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // SECTION 1 — What did they do?
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHAT DID \(partnerName.uppercased()) DO?")
                            .font(.caption.bold())
                            .foregroundStyle(headerColor)
                            .tracking(1.2)

                        TextField("They forgot...", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        ChipFlow(spacing: 8) {
                            ForEach(reasonChips, id: \.self) { chip in
                                PillChip(
                                    label: chip,
                                    isSelected: reason == chip,
                                    style: .filled
                                ) {
                                    reason = (reason == chip) ? "" : chip
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // SECTION 2 — How can they make it up?
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HOW CAN THEY MAKE IT UP? (OPTIONAL)")
                            .font(.caption.bold())
                            .foregroundStyle(headerColor)
                            .tracking(1.2)

                        TextField("They could...", text: $suggestion, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        ChipFlow(spacing: 8) {
                            ForEach(suggestionChips, id: \.self) { chip in
                                PillChip(
                                    label: chip,
                                    isSelected: suggestion == chip,
                                    style: .outlined
                                ) {
                                    suggestion = (suggestion == chip) ? "" : chip
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // SECTION 3 — Share with friends?
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $isPublic) {
                            HStack(spacing: 8) {
                                Text("📣")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share with friends")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(headerColor)
                                    Text(isPublic
                                         ? "Friends can see this and react. Two dogs in at once starts a jailbreak vote!"
                                         : "Just between you two.")
                                        .font(.caption)
                                        .foregroundStyle(headerColor.opacity(0.65))
                                }
                            }
                        }
                        .tint(Color(red: 0.68, green: 0.42, blue: 0.18))
                        .padding(14)
                        .background(Color.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)

                    // Space so content isn't hidden under sticky button
                    Color.clear.frame(height: 100)
                }
            }

            // Sticky bottom send button
            VStack(spacing: 6) {
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Text("⚠️  Send \(partnerName) to the DogHouse")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(reason.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.gray.opacity(0.35)
                        : sendColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .animation(.easeInOut(duration: 0.2), value: reason.isEmpty)

                if showError {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Costs 1 grace charge.")
                        .font(.caption)
                        .foregroundStyle(headerColor.opacity(0.65))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .background(
                bg
                    .shadow(color: .black.opacity(0.07), radius: 10, y: -4)
                    .ignoresSafeArea()
            )
        }
    }

    // MARK: - Send

    private func send() async {
        isSending = true
        showError = false
        do {
            let sug = suggestion.trimmingCharacters(in: .whitespaces)
            try await doghouseService.sendToDoghouse(
                reason: reason.trimmingCharacters(in: .whitespaces),
                suggestion: sug.isEmpty ? nil : sug,
                isPublic: isPublic
            )
            SoundService.shared.playSendToDoghouse()
            dismiss()
            onSent?()
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
        isSending = false
    }
}

// MARK: - Pill Chip

private struct PillChip: View {
    enum Style { case filled, outlined }

    let label: String
    let isSelected: Bool
    let style: Style
    let action: () -> Void

    private var selectedBg: Color { Color(red: 0.68, green: 0.42, blue: 0.18) }
    private var filledBg: Color { Color(red: 0.91, green: 0.83, blue: 0.70) }
    private var outlinedBg: Color { Color.white.opacity(0.75) }
    private var strokeColor: Color { Color(red: 0.72, green: 0.60, blue: 0.44) }
    private var textColor: Color { Color(red: 0.45, green: 0.32, blue: 0.18) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? selectedBg : (style == .filled ? filledBg : outlinedBg))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(style == .outlined && !isSelected ? strokeColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Flow Layout

private struct ChipFlow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        _ChipFlowLayout(spacing: spacing) { content }
    }
}

private struct _ChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var height: CGFloat = 0
        var rowX: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > maxWidth, rowX > 0 {
                height += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rowX: CGFloat = 0
        var rowY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > bounds.width, rowX > 0 {
                rowY += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + rowX, y: rowY),
                proposal: ProposedViewSize(size)
            )
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    SendToDoghouseSheet(
        doghouseService: DoghouseService(userId: "user1", partnerId: "user2"),
        partnerName: "Sam"
    )
}
