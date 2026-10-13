import LauncherCore
import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var backdropText: Color {
        model.wallpaper.image != nil && !reduceTransparency ? .white : .primary
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: LibraryDropDelegate(model: model, target: nil))
                VStack(spacing: 18) {
                    header
                    contentRegion
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: model.openFolderID
                        )
                    footer
                }
                .padding(.horizontal, 45)
                .padding(.top, max(48, geometry.safeAreaInsets.top + 20))
                .padding(.bottom, max(80, geometry.safeAreaInsets.bottom + 24))
                if model.draggedItem != nil {
                    HStack {
                        pageDropEdge(-1)
                        Spacer()
                        pageDropEdge(1)
                    }
                    .allowsHitTesting(true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launcher.surface")
        .accessibilityLabel(
            model.isPresentationReady ? "Sofla, Ready" : "Sofla, Preparing"
        )
        .accessibilityValue(model.isPresentationReady ? "Ready" : "Preparing")
    }

    private var contentRegion: some View {
        GeometryReader { geometry in
            if let folder = model.openFolder, model.query.isEmpty {
                folderContent(folder, availableSize: geometry.size)
            } else {
                let grid = DisplayGrid(size: geometry.size, preferences: model.preferences)
                Group {
                    if model.items.isEmpty {
                        emptyContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        applicationGrid(grid)
                            .frame(
                                height: grid.contentHeight + DisplayGrid.topInset,
                                alignment: .top
                            )
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .onAppear { model.fit(grid) }
                .onChange(of: geometry.size) { _, _ in model.fit(grid) }
                .onChange(of: model.preferences.grid) { _, _ in model.fit(grid) }
                .onChange(of: model.preferences.iconSize) { _, _ in model.fit(grid) }
            }
        }
    }

    @ViewBuilder private var background: some View {
        if let image = model.wallpaper.image, !reduceTransparency {
            Image(nsImage: image).resizable().scaledToFill().clipped()
                .overlay(.black.opacity(0.15))
                .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                LauncherSearchField(
                    text: $model.query, focusGeneration: model.focusGeneration,
                    submit: model.activateSelection, escape: model.escape,
                    navigate: { model.navigate($0 > 0 ? .down : .up) },
                    changePage: model.changePage,
                    horizontal: { model.navigate($0 < 0 ? .left : .right) },
                    didFocus: { model.performance.didFocusSearch(windowIsKey: $0) },
                    didUpdate: { model.performance.didUpdateSearch(query: $0) }
                )
                .frame(width: 300, height: 32)
                Spacer()
            }
            .frame(height: 32)
            ZStack {
                if model.preferences.showsFavorites || model.preferences.showsRecents {
                    HStack(spacing: 0) {
                        collectionButton("All apps", .all)
                        if model.preferences.showsFavorites {
                            collectionButton("Favorites", .favorites)
                        }
                        if model.preferences.showsRecents { collectionButton("Recents", .recents) }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 40)
                    .glassEffect(in: .capsule)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("launcher.collections")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
                if let confirmation = model.dropConfirmation {
                    Text(confirmation)
                        .font(.caption)
                        .foregroundStyle(backdropText)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .glassEffect(in: .capsule)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity)
                        .accessibilityIdentifier("launcher.dropConfirmation")
                        .accessibilityLabel(confirmation)
                }
            }
            .frame(height: 40)
        }
    }

    @ViewBuilder private func collectionButton(
        _ title: String, _ collection: LauncherPreferences.StartCollection
    ) -> some View {
        let button = Button {
            model.query = ""
            model.collection = collection
            model.focusGeneration += 1
        } label: {
            Text(title)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background {
                    if model.collection == collection {
                        Capsule().fill(.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .contentShape(Rectangle())
        .accessibilityIdentifier("collection.\(collection.rawValue)")
        .accessibilityAddTraits(model.collection == collection ? .isSelected : [])
        if collection == .favorites {
            button.onDrop(of: [.text], delegate: FavoritesDropDelegate(model: model))
        } else {
            button
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 15) {
            if model.isScanning {
                ProgressView().controlSize(.large)
                Text("Finding your applications…").foregroundStyle(backdropText)
            } else if !model.query.isEmpty {
                Text("No applications found").font(.title2).foregroundStyle(backdropText)
                Text("Try another name or check your application folders in Settings.")
                    .foregroundStyle(backdropText.opacity(0.8))
                Button("Clear search") { model.query = "" }.buttonStyle(.glass)
            } else {
                Text(
                    model.collection == .favorites
                        ? "Your favorites belong here"
                        : model.collection == .recents
                            ? "No recent applications" : "No applications to show"
                )
                .font(.title2)
                .foregroundStyle(backdropText)
                Button("Open Settings") { model.onPreferences?() }.buttonStyle(.glass)
            }
        }
        .accessibilityIdentifier("launcher.empty")
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(0..<model.pageCount, id: \.self) { page in
                    Button {
                        model.requestPage(page)
                    } label: {
                        Circle().fill(backdropText.opacity(page == model.page ? 1 : 0.4))
                            .frame(width: 7, height: 7)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Page \(page + 1)")
                    .accessibilityAddTraits(page == model.page ? .isSelected : [])
                }
            }
            .opacity(model.pageCount > 1 ? 1 : 0)
            .allowsHitTesting(model.pageCount > 1)
            .accessibilityHidden(model.pageCount <= 1)
            HStack {
                if model.preferences.showsKeyboardHints {
                    Text("↵ Open   ← ↑ ↓ → Select   ⌘← ⌘→ Page   esc Back")
                        .font(.caption).foregroundStyle(backdropText.opacity(0.8))
                }
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
            }
        }
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            if let message = model.launchFailure ?? model.message ?? model.catalogMessage {
                messageBanner(message).offset(y: -40)
            }
        }
    }

    private func messageBanner(_ message: String) -> some View {
        HStack {
            Text(message).font(.callout).textSelection(.enabled)
            if model.hasBackup { Button("Restore backup", action: model.restoreBackup) }
            if model.recoveryLocked { Button("Import…", action: model.importLayout) }
            if let app = model.lastFailedLaunch {
                Button("Retry") { model.activate(.application(app.id)) }
            }
            Button {
                model.dismissMessage()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(12).glassEffect(in: .rect(cornerRadius: 12))
        .accessibilityIdentifier("launcher.message")
    }

    private func pageDropEdge(_ delta: Int) -> some View {
        Rectangle().fill(.clear).frame(width: 30)
            .contentShape(Rectangle())
            .onDrop(of: [.text], delegate: PageDropDelegate(model: model, delta: delta))
    }
}
