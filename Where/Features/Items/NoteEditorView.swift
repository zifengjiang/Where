import SwiftUI

struct NoteEditorView: View {
    let isReadOnly: Bool
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(initialText: String, isReadOnly: Bool = false, onSave: @escaping (String) -> Void) {
        self.isReadOnly = isReadOnly; self.onSave = onSave; _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $text).font(.body).disabled(isReadOnly)
                    .accessibilityLabel(isReadOnly ? "Full note" : "Note")
                Text("\(text.count) characters").font(.caption).foregroundStyle(.secondary)
            }.padding()
            .navigationTitle(isReadOnly ? "Note" : "Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isReadOnly ? "Done" : "Cancel") { dismiss() } }
                if !isReadOnly { ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(text); dismiss() } } }
            }
        }
    }
}
