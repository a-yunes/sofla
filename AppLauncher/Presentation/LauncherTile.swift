import LauncherCore
import SwiftUI

enum LauncherTileDropPresentation: Equatable {
    case none
    case folderDestination
    case mergeCandidate
}

struct LauncherTile: View {
    let title: String
    let iconURLs: [URL]
    let iconSize: CGFloat
    let selected: Bool
    let dropPresentation: LauncherTileDropPresentation
    let isFolder: Bool
    let icons: ApplicationIconCache
    let overWallpaper: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon
                    .scaleEffect(iconScale)
                    .offset(y: iconOffset)
                    .frame(width: iconSize + 12, height: iconSize + 12)
                    .background {
                        if isHovered || dropPresentation != .none {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    .primary.opacity(
                                        dropPresentation == .none ? 0.08 : 0.16
                                    )
                                )
                                .shadow(
                                    color: dropPresentation == .none
                                        ? .clear : .black.opacity(0.24),
                                    radius: 10, y: 5
                                )
                        }
                        if selected && dropPresentation == .none {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.accentColor.opacity(0.3))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.primary.opacity(0.7), lineWidth: 2)
                                }
                        }
                    }
                Text(title)
                    .foregroundStyle(
                        overWallpaper && !reduceTransparency ? Color.white : Color.primary
                    )
                    .shadow(
                        color: overWallpaper && !reduceTransparency
                            ? Color.black.opacity(0.7) : .clear, radius: 2, y: 1
                    )
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: dropPresentation)
        .onDisappear { isHovered = false }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(isFolder ? "Folder" : "Application")
        .help(title)
    }

    private var iconScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if dropPresentation == .mergeCandidate { return 1.06 }
        return isHovered ? 1.07 : 1
    }

    private var iconOffset: CGFloat {
        guard !reduceMotion, dropPresentation == .none, isHovered else { return 0 }
        return -3
    }

    @ViewBuilder
    private var icon: some View {
        if isFolder {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2
            ) {
                ForEach(Array(iconURLs.prefix(9).enumerated()), id: \.offset) { _, url in
                    CachedApplicationIcon(entry: icons.entry(for: url, size: iconSize / 4))
                }
            }
            .padding(9)
            .frame(width: iconSize, height: iconSize)
            .glassEffect(in: .rect(cornerRadius: 18))
        } else if let url = iconURLs.first {
            CachedApplicationIcon(entry: icons.entry(for: url, size: iconSize))
                .frame(width: iconSize, height: iconSize)
        }
    }
}

private struct CachedApplicationIcon: View {
    let entry: ApplicationIconEntry

    var body: some View {
        Image(nsImage: entry.image)
            .resizable()
            .scaledToFit()
    }
}
