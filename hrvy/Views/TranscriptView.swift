import SwiftUI

/// The live "Hearing: …" strip at the top of the window.
struct TranscriptView: View {
    let text: String
    let isListening: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isListening ? "waveform" : "waveform.slash")
                .foregroundStyle(isListening ? Color.accentColor : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: isListening)
                .frame(width: 18)

            Text("Hearing")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)

            Text(displayText)
                .font(.callout)
                .italic(!text.isEmpty)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var displayText: String {
        if !text.isEmpty { return "“…\(text)…”" }
        return isListening ? "Waiting for speech…" : "Not listening"
    }
}

#Preview {
    TranscriptView(text: "remain irrational longer than you can remain", isListening: true)
}
