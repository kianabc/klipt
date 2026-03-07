import SwiftUI
import AppKit

struct ClipItemView: View {
    let item: ClipItem
    let onSelect: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Color-coded type icon
            Image(systemName: item.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(item.type.color)
                .frame(width: 24, height: 24)
                .background(item.type.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            // Content preview
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metadata
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.createdAt.relativeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            // Actions on hover
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onPin) {
                        Image(systemName: item.isPinned ? "pin.slash" : "pin")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin" : "Pin")

                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.7))
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .onDrag {
            provideItemForDrag()
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text:
            Text(item.displayTitle)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.primary)

        case .image:
            if let image = item.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("Image")
                    .foregroundStyle(.secondary)
            }

        case .file:
            HStack(spacing: 6) {
                if let url = item.resolvedFileURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text(item.displayTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func provideItemForDrag() -> NSItemProvider {
        let provider = NSItemProvider()

        switch item.type {
        case .text:
            if let text = item.textContent {
                provider.registerDataRepresentation(forTypeIdentifier: "public.utf8-plain-text", visibility: .all) { completion in
                    completion(text.data(using: .utf8), nil)
                    return nil
                }
            }
        case .image:
            if let data = item.imageData {
                provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
        case .file:
            if let url = item.resolvedFileURL {
                provider.registerFileRepresentation(forTypeIdentifier: "public.data", visibility: .all) { completion in
                    completion(url, true, nil)
                    return nil
                }
            }
        }

        return provider
    }
}

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
