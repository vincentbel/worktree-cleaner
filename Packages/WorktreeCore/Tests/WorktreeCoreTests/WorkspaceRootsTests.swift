import Foundation
import XCTest

@testable import WorktreeCore

final class WorkspaceRootsTests: XCTestCase {
  func testAcceptsSiblingDirectories() throws {
    var roots = WorkspaceRoots()

    try roots.add(URL(filePath: "/tmp/dev-a", directoryHint: .isDirectory))
    try roots.add(URL(filePath: "/tmp/dev-b", directoryHint: .isDirectory))

    XCTAssertEqual(roots.urls.count, 2)
  }

  func testRejectsDuplicateDirectory() throws {
    var roots = WorkspaceRoots()
    let root = URL(filePath: "/tmp/dev", directoryHint: .isDirectory)
    try roots.add(root)

    XCTAssertThrowsError(try roots.add(root)) { error in
      guard case WorkspaceRootError.duplicate = error else {
        return XCTFail("Expected duplicate, got \(error)")
      }
    }
  }

  func testRejectsNestedDirectoryInEitherOrder() throws {
    let parent = URL(filePath: "/tmp/dev", directoryHint: .isDirectory)
    let child = URL(filePath: "/tmp/dev/github", directoryHint: .isDirectory)

    var parentFirst = WorkspaceRoots()
    try parentFirst.add(parent)
    XCTAssertThrowsError(try parentFirst.add(child)) { error in
      guard case WorkspaceRootError.overlaps(let existing) = error else {
        return XCTFail("Expected overlap, got \(error)")
      }
      XCTAssertEqual(existing, parent)
    }

    var childFirst = WorkspaceRoots()
    try childFirst.add(child)
    XCTAssertThrowsError(try childFirst.add(parent)) { error in
      guard case WorkspaceRootError.overlaps(let existing) = error else {
        return XCTFail("Expected overlap, got \(error)")
      }
      XCTAssertEqual(existing, child)
    }
  }
}
