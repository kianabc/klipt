import SwiftUI
import UniformTypeIdentifiers

struct DropTargetView: View {
    let store: ClipboardStore
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.clear,
                style: StrokeStyle(lineWidth: 2, dash: [6])
            )
            .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // File URLs
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(fileURL: url))
                    }
                }
                return
            }

            // Images
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(imageData: data))
                    }
                }
                return
            }

            // Text
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data = data as? Data,
                          let text = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        store.add(ClipItem(text: text))
                    }
                }
                return
            }
        }
    }
}
