import Foundation
import XCTest

@testable import WorktreeCore

final class RepositoryCatalogTests: XCTestCase {
  func testRepositoryFoundUnderTwoRootsAppearsOnlyOnce() {
    let rootA = URL(filePath: "/tmp/a", directoryHint: .isDirectory)
    let rootB = URL(filePath: "/tmp/b", directoryHint: .isDirectory)
    let repository = makeRepository()
    var catalog = RepositoryCatalog()

    catalog.register(repository, foundUnder: rootA)
    catalog.register(repository, foundUnder: rootB)

    XCTAssertEqual(catalog.repositories, [repository])
    XCTAssertEqual(catalog.repositories(under: rootA), [repository])
    XCTAssertEqual(catalog.repositories(under: rootB), [repository])
    XCTAssertEqual(
      Set(catalog.associations.first?.rootIDs ?? []),
      Set([rootA, rootB])
    )
  }

  func testReconcileRemovesOnlyTheFinishedRootsMembership() {
    let rootA = URL(filePath: "/tmp/a", directoryHint: .isDirectory)
    let rootB = URL(filePath: "/tmp/b", directoryHint: .isDirectory)
    let repository = makeRepository()
    var catalog = RepositoryCatalog()
    catalog.register(repository, foundUnder: rootA)
    catalog.register(repository, foundUnder: rootB)

    let firstRemoval = catalog.reconcile(root: rootA, discoveredRepositoryIDs: [])

    XCTAssertTrue(firstRemoval.isEmpty)
    XCTAssertEqual(catalog.repositories, [repository])
    XCTAssertTrue(catalog.repositories(under: rootA).isEmpty)
    XCTAssertEqual(catalog.repositories(under: rootB), [repository])

    let secondRemoval = catalog.reconcile(root: rootB, discoveredRepositoryIDs: [])

    XCTAssertEqual(secondRemoval, [repository.id])
    XCTAssertTrue(catalog.repositories.isEmpty)
  }

  func testCatalogRestoresPersistedAssociations() {
    let root = URL(filePath: "/tmp/a", directoryHint: .isDirectory)
    let repository = makeRepository()
    let catalog = RepositoryCatalog(
      repositories: [repository],
      associations: [
        RepositoryRootAssociation(repositoryID: repository.id, rootIDs: [root])
      ]
    )

    XCTAssertEqual(catalog.repositories(under: root), [repository])
  }

  private func makeRepository() -> GitRepository {
    GitRepository(
      workingTreeURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
      commonGitDirectoryURL: URL(filePath: "/tmp/project/.git", directoryHint: .isDirectory),
      linkedWorktreeCount: 2
    )
  }
}
