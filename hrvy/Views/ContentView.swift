import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if model.book != nil {
                TranscriptView(text: model.transcriptText, isListening: model.isListening)
                Divider()
            }
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.book?.title ?? "hrvy")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .inspector(isPresented: $model.isDebugPanelVisible) {
            DebugPanel(model: model)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .fileImporter(isPresented: $model.isImporterPresented, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                model.openBook(at: url)
            }
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { alert in
            if let settingsURL = alert.settingsURL {
                Button("Open System Settings") { openURL(settingsURL) }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if model.isLoadingBook {
            ProgressView("Reading and indexing book…")
        } else if model.book == nil {
            ContentUnavailableView {
                Label("No Book Loaded", systemImage: "book.closed")
            } description: {
                Text("Open a PDF with selectable text. When someone reads a line from it aloud, hrvy finds the passage and shows what comes next.")
            } actions: {
                Button("Open Book…") { model.isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if let book = model.book, let match = model.currentMatch {
            PassageView(
                book: book,
                match: match,
                configuration: model.configuration,
                showsConfidence: model.isDebugPanelVisible,
                isLive: model.status == .matchFound
            )
        } else if model.isListening {
            ContentUnavailableView(
                "Listening for a Passage",
                systemImage: "waveform",
                description: Text("Read or quote a few consecutive words from the book.")
            )
            .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            ContentUnavailableView {
                Label("Ready", systemImage: "book")
            } description: {
                Text("Start listening, then read any line from the book — beginning anywhere.")
            } actions: {
                Button("Start Listening") { model.toggleListening() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StatusBadge(status: model.status)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isImporterPresented = true
            } label: {
                Label("Open Book", systemImage: "doc.badge.plus")
            }
            .help("Open a PDF book (⌘O)")

            Button {
                model.toggleListening()
            } label: {
                Label(model.isListening ? "Stop Listening" : "Start Listening",
                      systemImage: model.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.book == nil || model.isStartingToListen)
            .help(model.isListening ? "Stop listening (⌘L)" : "Start listening (⌘L)")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.isDebugPanelVisible) {
                Label("Debug", systemImage: "ladybug")
            }
            .help("Show matching diagnostics (⌥⌘D)")
        }
    }

    private var subtitle: String {
        guard let book = model.book else { return "" }
        return "\(book.pageCount) pages · \(book.words.count.formatted()) words"
    }
}

struct StatusBadge: View {
    let status: AppViewModel.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse, isActive: status == .listening)
            Text(status.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .animation(.default, value: status)
    }

    private var color: Color {
        switch status {
        case .noBook, .loading: .gray
        case .ready: .blue
        case .listening: .orange
        case .matchFound: .green
        }
    }
}

#Preview {
    ContentView(model: AppViewModel())
}
