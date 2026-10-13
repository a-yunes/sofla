import LauncherCore
import SwiftUI

extension LauncherView {
    func applicationGrid(_ grid: DisplayGrid) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(grid.cellWidth), spacing: 0), count: grid.columns),
            spacing: DisplayGrid.rowSpacing
        ) {
            ForEach(Array(model.pageItems.enumerated()), id: \.element.id) { index, item in
                gridCell(item, index: index, grid: grid)
            }
        }
        .frame(width: grid.contentWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 6)
        .accessibilityIdentifier("launcher.grid")
        .task(id: model.page) {
            await model.prewarmAdjacentPage(iconSize: grid.iconSize)
        }
    }

    private func gridCell(_ item: LauncherCore.LibraryItem, index: Int, grid: DisplayGrid)
        -> some View
    {
        HStack(spacing: 0) {
            Rectangle().fill(
                model.dropTarget == .insertion(beforeItemID: item.id) ? Color.accentColor : .clear
            )
            .frame(width: 6, height: grid.iconSize)
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: LibraryDropDelegate(
                    model: model, target: item,
                    insertion: model.page * model.capacity + index))
            tile(item, grid: grid, index: model.page * model.capacity + index)
        }
        .frame(height: grid.cellHeight)
    }

    @ViewBuilder private func tile(_ item: LauncherCore.LibraryItem, grid: DisplayGrid, index: Int)
        -> some View
    {
        switch item {
        case .application(let id):
            if let app = model.record(id) {
                LauncherTile(
                    title: app.name, iconURLs: [app.url], iconSize: grid.iconSize,
                    selected: model.selection == index
                        && (model.showsKeyboardSelection || !model.query.isEmpty),
                    dropPresentation: model.dropTarget == .applicationMerge(id)
                        ? .mergeCandidate : .none,
                    isFolder: false, icons: model.icons,
                    overWallpaper: model.wallpaper.image != nil
                        && (model.openFolderID == nil || !model.query.isEmpty)
                ) { model.activate(item) }
                .accessibilityIdentifier("app.\(app.id)")
                .task(id: app.url) { await model.prepareTrashEligibility(for: app) }
                .contextMenu { ApplicationActions(model: model, app: app) }
                .draggable(item.id) {
                    ApplicationDragPreview(
                        entry: model.icons.entry(for: app.url, size: grid.iconSize),
                        size: grid.iconSize * 0.7
                    )
                }
                .dragConfiguration(
                    .init(
                        operationsWithinApp: .init(
                            allowCopy: model.canDrag, allowMove: model.canDrag),
                        operationsOutsideApp: .init(allowCopy: false)
                    )
                )
                .onDragSessionUpdated { session in
                    switch session.phase {
                    case .initial, .active:
                        guard model.canDrag else { return }
                        model.draggedItem = item
                    case .ended:
                        model.stopDragPaging()
                        model.draggedItem = nil
                        model.dropTarget = nil
                    default: break
                    }
                }
                .onDrop(of: [.text], delegate: LibraryDropDelegate(model: model, target: item))
            }
        case .folder(let id):
            if let folder = model.folder(id) {
                LauncherTile(
                    title: folder.name,
                    iconURLs: folder.applicationIDs.filter { !model.library.hiddenIDs.contains($0) }
                        .compactMap { model.record($0)?.url },
                    iconSize: grid.iconSize,
                    selected: model.showsKeyboardSelection && model.selection == index,
                    dropPresentation: model.dropTarget == .folder(id)
                        ? .folderDestination : .none,
                    isFolder: true, icons: model.icons, overWallpaper: model.wallpaper.image != nil
                ) { model.activate(item) }
                .accessibilityIdentifier("folder.\(id)")
                .contextMenu {
                    Button("Rename…") { model.renameFolder(folder) }
                    Button("Ungroup folder") {
                        model.execute(
                            .ungroupFolder(id: id, destination: index), name: "Ungroup folder")
                    }
                    Button("Move to beginning") {
                        model.execute(
                            .reorderRoot(itemID: item.id, destination: 0), name: "Move folder")
                    }
                }
                .draggable(item.id)
                .dragConfiguration(
                    .init(
                        operationsWithinApp: .init(allowCopy: false, allowMove: model.canDrag),
                        operationsOutsideApp: .init(allowCopy: false)
                    )
                )
                .onDragSessionUpdated { session in
                    switch session.phase {
                    case .initial, .active:
                        guard model.canDrag else { return }
                        model.draggedItem = item
                    case .ended:
                        model.stopDragPaging()
                        model.draggedItem = nil
                        model.dropTarget = nil
                    default: break
                    }
                }
                .onDrop(of: [.text], delegate: LibraryDropDelegate(model: model, target: item))
            }
        }
    }

    func folderContent(_ folder: ApplicationFolder, availableSize: CGSize) -> some View {
        let innerSize = CGSize(
            width: min(852, max(100, availableSize.width - 48)),
            height: max(120, availableSize.height - 144))
        let grid = DisplayGrid(
            size: innerSize, preferences: model.preferences,
            compactItemCount: model.items.count)
        return VStack(spacing: 20) {
            HStack {
                Button {
                    model.openFolderID = nil
                } label: {
                    Label("All apps", systemImage: "chevron.left")
                }
                .buttonStyle(.glass).accessibilityIdentifier("folder.back")
                .frame(width: 110, alignment: .leading)
                Spacer()
                Button(folder.name) { model.renameFolder(folder) }
                    .font(.title2).buttonStyle(.plain).lineLimit(1)
                Spacer()
                Text(model.items.count == 1 ? "1 app" : "\(model.items.count) apps").font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
            applicationGrid(grid)
                .frame(height: grid.contentHeight + DisplayGrid.topInset)
                .onAppear { model.fit(grid) }
                .onChange(of: availableSize) { _, _ in model.fit(grid) }
                .onChange(of: model.preferences.grid) { _, _ in model.fit(grid) }
                .onChange(of: model.preferences.iconSize) { _, _ in model.fit(grid) }
            Text("Drag an app outside this folder to move it to All apps.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: min(900, max(440, grid.contentWidth + 48)))
        .glassEffect(in: .rect(cornerRadius: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .transition(
            reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98))
        )
        .accessibilityIdentifier("launcher.folder")
    }

}

private struct ApplicationDragPreview: View {
    let entry: ApplicationIconEntry
    let size: CGFloat

    var body: some View {
        Image(nsImage: entry.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(1)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
    }
}
