import Foundation
import XCTest
@testable import Gizmo

final class WorkspaceMappingStoreTests: XCTestCase {
  func testRoundTripSaveAndLoad() throws {
    let fileURL = try makeTemporaryFileURL()
    let store = FileWorkspaceMappingStore(fileURL: fileURL)

    let snapshot = WorkspaceMappingSnapshot(
      activeWorkspaceNamesByDisplay: [WorkspaceDisplayRole.primary.rawValue: "2"],
      workspaceWindows: [
        "1": ["axwn:100", "axwn:200"],
        "2": ["axwn:300"],
      ],
      savedFrames: [
        "axwn:100": PersistedWindowFrame(x: 10, y: 20, width: 400, height: 300),
        "axwn:300": PersistedWindowFrame(x: 40, y: 50, width: 700, height: 500),
      ]
    )

    store.save(snapshot)
    let loaded = store.load()

    XCTAssertEqual(loaded, snapshot)
  }

  func testLoadReturnsNilForUnsupportedVersion() throws {
    let fileURL = try makeTemporaryFileURL()
    let payload = """
      {
        "version" : 999,
        "workspaceWindows" : {
          "1" : [
            "axwn:100"
          ]
        }
      }
      """
    try Data(payload.utf8).write(to: fileURL, options: .atomic)

    let store = FileWorkspaceMappingStore(fileURL: fileURL)
    XCTAssertNil(store.load())
  }

  func testLoadWithoutSavedFramesUsesEmptyDefault() throws {
    let fileURL = try makeTemporaryFileURL()
    let payload = """
      {
        "version" : 1,
        "workspaceWindows" : {
          "1" : [
            "axwn:100"
          ]
        }
      }
      """
    try Data(payload.utf8).write(to: fileURL, options: .atomic)

    let store = FileWorkspaceMappingStore(fileURL: fileURL)
    let snapshot = try XCTUnwrap(store.load())

    XCTAssertTrue(snapshot.activeWorkspaceNamesByDisplay.isEmpty)
    XCTAssertEqual(snapshot.workspaceWindows, ["1": ["axwn:100"]])
    XCTAssertEqual(snapshot.savedFrames, [:])
  }

  private func makeTemporaryFileURL() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    return directoryURL.appendingPathComponent("workspace-mapping.json", isDirectory: false)
  }
}
