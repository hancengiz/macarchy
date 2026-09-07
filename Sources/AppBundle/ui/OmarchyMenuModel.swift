import Combine
import Foundation

@MainActor
final class OmarchyMenuModel: ObservableObject {
    @Published var query = "" { didSet { selectedIndex = 0 } }
    @Published var selectedIndex = 0
    @Published private(set) var activeMenu = "root"
    private(set) var navStack: [String] = []
    let store = OmarchyMenuStore.shared

    var headerTitle: String {
        // Title only: echoing the query here duplicated the text visually.
        store.nodes[activeMenu].map { $0.title ?? $0.label } ?? activeMenu
    }

    var rows: [OmarchyMenuRow] {
        query.isEmpty ? store.rows(for: activeMenu) : store.search(menuId: activeMenu, query: query)
    }

    var isSearching: Bool { !query.isEmpty }

    func isSelectable(_ row: OmarchyMenuRow) -> Bool { !row.isDivider && !row.isDisabled }

    var selection: OmarchyMenuRow? {
        let allRows = rows
        if allRows.indices.contains(selectedIndex), isSelectable(allRows[selectedIndex]) {
            return allRows[selectedIndex]
        }
        return allRows.first(where: isSelectable)
    }

    func moveSelection(_ offset: Int) {
        let indices = rows.indices.filter { isSelectable(rows[$0]) }
        guard !indices.isEmpty else { selectedIndex = 0; return }
        let current = indices.firstIndex(of: selectedIndex) ?? 0
        selectedIndex = indices[(current + offset % indices.count + indices.count) % indices.count]
    }

    func enter(_ row: OmarchyMenuRow) {
        guard row.isSubmenu, let node = row.node else { return }
        navStack.append(activeMenu)
        activeMenu = node.target ?? node.id
        query = ""
        selectedIndex = 0
    }

    /// Backspace/Left with an empty filter. Returns false at the root (no-op).
    @discardableResult
    func back() -> Bool {
        guard let previous = navStack.popLast() else { return false }
        activeMenu = previous
        query = ""
        selectedIndex = 0
        return true
    }

    func resetToRoot() {
        navStack = []
        activeMenu = "root"
        query = ""
        selectedIndex = 0
    }
}
