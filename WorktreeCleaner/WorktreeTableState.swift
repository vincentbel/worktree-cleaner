import Foundation
import WorktreeCore

enum WorktreeSortColumn: String {
  case commitDate
  case diskUsage
  case branch
  case path

  var titleKey: String {
    switch self {
    case .commitDate: "column.last_commit"
    case .diskUsage: "column.disk_usage"
    case .branch: "column.branch"
    case .path: "column.path"
    }
  }
}

struct WorktreeSortOrder: Equatable {
  var column: WorktreeSortColumn = .commitDate
  var ascending = true

  mutating func toggle(_ column: WorktreeSortColumn) {
    if self.column == column {
      ascending.toggle()
    } else {
      self.column = column
      ascending = true
    }
  }

  func sorted(_ worktrees: [GitWorktree], allocatedBytes: [URL: Int64]) -> [GitWorktree] {
    worktrees.sorted { lhs, rhs in
      if lhs.isMain != rhs.isMain { return lhs.isMain }
      let comparison: Bool?
      switch column {
      case .commitDate:
        comparison = orderedBefore(lhs.commitDate, rhs.commitDate)
      case .diskUsage:
        comparison = orderedBefore(allocatedBytes[lhs.id], allocatedBytes[rhs.id])
      case .branch:
        let order = (lhs.branch ?? "Detached HEAD").localizedStandardCompare(
          rhs.branch ?? "Detached HEAD")
        comparison =
          order == .orderedSame
          ? nil : (ascending ? order == .orderedAscending : order == .orderedDescending)
      case .path:
        let order = lhs.path.path.localizedStandardCompare(rhs.path.path)
        comparison =
          order == .orderedSame
          ? nil : (ascending ? order == .orderedAscending : order == .orderedDescending)
      }
      if let comparison { return comparison }
      let branchOrder = (lhs.branch ?? "Detached HEAD").localizedStandardCompare(
        rhs.branch ?? "Detached HEAD")
      if branchOrder != .orderedSame { return branchOrder == .orderedAscending }
      return lhs.path.path.localizedStandardCompare(rhs.path.path) == .orderedAscending
    }
  }

  private func orderedBefore<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
    switch (lhs, rhs) {
    case (nil, nil): nil
    case (nil, _): false
    case (_, nil): true
    case (.some(let lhs), .some(let rhs)):
      lhs == rhs ? nil : (ascending ? lhs < rhs : lhs > rhs)
    }
  }
}

struct WorktreeBatchSelection {
  var selectedIDs: Set<GitWorktree.ID> = []
  private(set) var anchorID: GitWorktree.ID?

  mutating func set(
    _ id: GitWorktree.ID,
    selected: Bool,
    extendingRange: Bool,
    orderedSelectableIDs: [GitWorktree.ID]
  ) {
    guard let end = orderedSelectableIDs.firstIndex(of: id) else { return }
    let affectedIDs: Set<GitWorktree.ID>
    if extendingRange, let anchorID, let start = orderedSelectableIDs.firstIndex(of: anchorID) {
      affectedIDs = Set(orderedSelectableIDs[min(start, end)...max(start, end)])
    } else {
      affectedIDs = [id]
      anchorID = id
    }
    if selected {
      selectedIDs.formUnion(affectedIDs)
    } else {
      selectedIDs.subtract(affectedIDs)
    }
  }

  mutating func setAll(_ selected: Bool, selectableIDs: Set<GitWorktree.ID>) {
    if selected {
      selectedIDs.formUnion(selectableIDs)
    } else {
      selectedIDs.subtract(selectableIDs)
    }
    resetAnchor()
  }

  mutating func retain(_ selectableIDs: Set<GitWorktree.ID>) {
    selectedIDs.formIntersection(selectableIDs)
    if let anchorID, !selectableIDs.contains(anchorID) { resetAnchor() }
  }

  mutating func resetAnchor() {
    anchorID = nil
  }
}
