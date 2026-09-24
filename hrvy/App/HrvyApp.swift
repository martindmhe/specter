import SwiftUI

@main
struct HrvyApp: App {
    @State private var model = AppViewModel()

    var body: some Scene {
        Window("hrvy", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 900, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Book…") { model.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
            CommandMenu("Listening") {
                Button(model.isListening ? "Stop Listening" : "Start Listening") {
                    model.toggleListening()
                }
                .keyboardShortcut("l")
                .disabled(model.book == nil)

                Divider()

                Toggle("Show Debug Panel", isOn: Bindable(model).isDebugPanelVisible)
                    .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }
    }
}
