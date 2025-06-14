import SwiftUI

struct SpeakerRenameView: View {
    let speakerId: Int
    let currentName: String
    @Binding var newName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Rename Speaker")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Speaker \(speakerId + 1)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Speaker Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter speaker name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSave()
                        }
                    }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .onAppear {
            newName = currentName
            isTextFieldFocused = true
        }
    }
}

#Preview {
    SpeakerRenameView(
        speakerId: 0,
        currentName: "Speaker 1",
        newName: .constant("John Doe"),
        onSave: {},
        onCancel: {}
    )
    .padding()
    #if os(iOS)
    .background(Color(.systemBackground))
    #else
    .background(Color(NSColor.controlBackgroundColor))
    #endif
}
