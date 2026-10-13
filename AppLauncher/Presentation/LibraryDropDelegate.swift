import LauncherCore
import SwiftUI

struct LibraryDropDelegate: DropDelegate {
    let model: LauncherModel
    let target: LauncherCore.LibraryItem?
    var insertion: Int?

    private var presentationTarget: LauncherModel.DropTarget? {
        if insertion != nil { return .insertion(beforeItemID: target?.id) }
        guard case .application = model.draggedItem else { return nil }
        switch target {
        case .application(let id): return .applicationMerge(id)
        case .folder(let id): return .folder(id)
        case nil: return nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard model.canDrag, let source = model.draggedItem,
            info.hasItemsConforming(to: [.text])
        else { return false }
        if insertion != nil { return true }
        guard case .application = source else { return false }
        return target != nil || model.openFolderID != nil
    }
    func dropEntered(info: DropInfo) {
        model.dropTarget = presentationTarget
    }
    func dropExited(info: DropInfo) {
        if model.dropTarget == presentationTarget { model.dropTarget = nil }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let source = model.draggedItem else { return false }
        model.stopDragPaging()
        model.drop(source, onto: target, insertion: insertion)
        return true
    }
}

struct FavoritesDropDelegate: DropDelegate {
    let model: LauncherModel

    func validateDrop(info: DropInfo) -> Bool {
        guard model.canDrag, case .application = model.draggedItem else { return false }
        return info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) { model.dropTarget = .favorites }

    func dropExited(info: DropInfo) {
        if model.dropTarget == .favorites { model.dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        guard let source = model.draggedItem else { return false }
        defer {
            model.stopDragPaging()
            model.draggedItem = nil
            model.dropTarget = nil
        }
        return model.dropOnFavorites(source)
    }
}

struct PageDropDelegate: DropDelegate {
    let model: LauncherModel
    let delta: Int
    func validateDrop(info: DropInfo) -> Bool {
        model.canDrag && model.draggedItem != nil && info.hasItemsConforming(to: [.text])
    }
    func dropEntered(info: DropInfo) { model.startDragPaging(delta) }
    func dropExited(info: DropInfo) { model.stopDragPaging() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        model.stopDragPaging()
        return false
    }
}
