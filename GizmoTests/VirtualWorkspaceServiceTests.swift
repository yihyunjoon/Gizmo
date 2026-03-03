import AppKit
import CoreGraphics
import XCTest
@testable import Gizmo

@MainActor
final class VirtualWorkspaceServiceTests: XCTestCase {
  private final class FakeWorkspaceWindowDriver: WorkspaceWindowDriver {
    var accessibilityGranted = true
    var focusedWindow: ManagedWindowRef?
    var visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var framesByWindowKey: [WindowKey: CGRect] = [:]
    var failingSetFrameKeys: Set<WindowKey> = []

    func isAccessibilityGranted() -> Bool {
      accessibilityGranted
    }

    func resolveFocusedWindow(preferredWindow: AXUIElement?) -> ManagedWindowRef? {
      focusedWindow
    }

    func frame(for window: ManagedWindowRef) -> CGRect? {
      framesByWindowKey[window.key]
    }

    func setFrame(_ frame: CGRect, for window: ManagedWindowRef) -> Bool {
      guard isWindowAlive(window) else { return false }
      guard !failingSetFrameKeys.contains(window.key) else { return false }

      framesByWindowKey[window.key] = frame
      return true
    }

    func isWindowAlive(_ window: ManagedWindowRef) -> Bool {
      framesByWindowKey[window.key] != nil
    }

    func singleMonitorVisibleFrame() -> CGRect? {
      visibleFrame
    }
  }

  func testFocusWorkspaceUpdatesActiveAndPrevious() {
    let driver = FakeWorkspaceWindowDriver()
    let service = makeService(
      driver: driver,
      enabled: true,
      names: ["1", "2"]
    )

    let firstWindow = registerWindow(
      key: "w1",
      frame: CGRect(x: 10, y: 10, width: 800, height: 600),
      in: driver
    )
    driver.focusedWindow = firstWindow
    assertSuccess(service.moveFocusedWindowToWorkspace("1"))

    let secondWindowOriginalFrame = CGRect(x: 40, y: 40, width: 700, height: 500)
    let secondWindow = registerWindow(
      key: "w2",
      frame: secondWindowOriginalFrame,
      in: driver
    )
    driver.focusedWindow = secondWindow
    assertSuccess(service.moveFocusedWindowToWorkspace("2"))

    let secondWindowHiddenFrame = try? XCTUnwrap(driver.framesByWindowKey[secondWindow.key])
    XCTAssertNotNil(secondWindowHiddenFrame)
    XCTAssertTrue((secondWindowHiddenFrame?.minX ?? 0) > (driver.visibleFrame?.maxX ?? 0))

    assertSuccess(service.focusWorkspace("2"))
    XCTAssertEqual(service.state.activeWorkspaceName, "2")
    XCTAssertEqual(service.state.previousWorkspaceName, "1")
    XCTAssertEqual(driver.framesByWindowKey[secondWindow.key], secondWindowOriginalFrame)

    let firstWindowFrame = try? XCTUnwrap(driver.framesByWindowKey[firstWindow.key])
    XCTAssertNotNil(firstWindowFrame)
    XCTAssertTrue((firstWindowFrame?.minX ?? 0) > (driver.visibleFrame?.maxX ?? 0))
  }

  func testFocusPreviousWorkspaceTogglesBackAndForth() {
    let driver = FakeWorkspaceWindowDriver()
    let service = makeService(
      driver: driver,
      enabled: true,
      names: ["1", "2"]
    )

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    assertSuccess(service.focusWorkspace("2"))
    XCTAssertEqual(service.state.activeWorkspaceName, "2")
    XCTAssertEqual(service.state.previousWorkspaceName, "1")

    assertSuccess(service.focusPreviousWorkspace())
    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertEqual(service.state.previousWorkspaceName, "2")
  }

  func testMoveFocusedWindowToWorkspaceReassignsMembership() {
    let driver = FakeWorkspaceWindowDriver()
    let service = makeService(
      driver: driver,
      enabled: true,
      names: ["1", "2", "3"]
    )

    let window = registerWindow(
      key: "window-a",
      frame: CGRect(x: 100, y: 100, width: 500, height: 400),
      in: driver
    )
    driver.focusedWindow = window

    assertSuccess(service.moveFocusedWindowToWorkspace("2"))
    XCTAssertEqual(service.managedWindowKeys(in: "1"), [])
    XCTAssertEqual(service.managedWindowKeys(in: "2"), ["window-a"])

    assertSuccess(service.moveFocusedWindowToWorkspace("3"))
    XCTAssertEqual(service.managedWindowKeys(in: "2"), [])
    XCTAssertEqual(service.managedWindowKeys(in: "3"), ["window-a"])
  }

  func testDisabledWorkspaceModeReturnsError() {
    let driver = FakeWorkspaceWindowDriver()
    let service = makeService(
      driver: driver,
      enabled: false,
      names: ["1", "2"]
    )

    assertFailure(.workspaceDisabled, in: service.focusWorkspace("2"))
  }

  func testInvalidWorkspaceReturnsError() {
    let driver = FakeWorkspaceWindowDriver()
    let service = makeService(
      driver: driver,
      enabled: true,
      names: ["1"]
    )

    assertFailure(.invalidWorkspace, in: service.focusWorkspace("nope"))
  }

  private func makeService(
    driver: FakeWorkspaceWindowDriver,
    enabled: Bool,
    names: [String]
  ) -> VirtualWorkspaceService {
    VirtualWorkspaceService(
      driver: driver,
      initialConfig: WorkspaceConfig(
        enabled: enabled,
        names: names,
        hideStrategy: .cornerOffscreen
      )
    )
  }

  private func registerWindow(
    key: String,
    frame: CGRect,
    in driver: FakeWorkspaceWindowDriver
  ) -> ManagedWindowRef {
    driver.framesByWindowKey[key] = frame
    return ManagedWindowRef(key: key, element: nil)
  }

  private func assertSuccess(
    _ result: Result<Void, WorkspaceError>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    switch result {
    case .success:
      return
    case .failure(let error):
      XCTFail("Expected success, got failure: \(error)", file: file, line: line)
    }
  }

  private func assertFailure(
    _ expected: WorkspaceError,
    in result: Result<Void, WorkspaceError>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    switch result {
    case .success:
      XCTFail("Expected failure \(expected), got success", file: file, line: line)
    case .failure(let error):
      XCTAssertEqual(error, expected, file: file, line: line)
    }
  }
}
