import SwiftUI

struct NoteEditorView: View {
    let isReadOnly: Bool
    let footer: String?
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(initialText: String, isReadOnly: Bool = false, footer: String? = nil, onSave: @escaping (String) -> Void) {
        self.isReadOnly = isReadOnly; self.footer = footer; self.onSave = onSave; _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $text).font(.body).disabled(isReadOnly)
                    .accessibilityLabel(isReadOnly ? "完整备忘" : "备忘")
                if !isReadOnly { Text("\(text.count) 个字符").font(.caption).foregroundStyle(.secondary) }
                if let footer { Text(footer).font(.caption).foregroundStyle(.secondary).accessibilityLabel(footer) }
            }.padding()
            .navigationTitle(isReadOnly ? "完整备忘" : "编辑备忘")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isReadOnly ? "完成" : "取消") { dismiss() } }
                if !isReadOnly { ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(text); dismiss() } } }
            }
        }
    }
}
