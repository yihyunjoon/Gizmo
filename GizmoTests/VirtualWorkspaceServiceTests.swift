import ApplicationServices
import CoreGraphics
import XCTest
@testable import Gizmo

@MainActor
final class VirtualWorkspaceServiceTests: XCTestCase {
  func testClosedFocusedWindowRestoresTopmostWindowInSameWorkspace() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")
    let window3 = makeWindow(key: "axwn:300")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2, window3],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
        window3.key: CGRect(x: 40, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window3
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.focusedWindow = window2
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.removeWindow(window2.key)
    driver.focusedWindow = window3
    driver.resetRecordedCalls()

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertEqual(driver.focusCalls, [window1.key])
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testClosedFocusedWindowDoesNotSwitchToOtherWorkspaceWindow() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")
    let window3 = makeWindow(key: "axwn:300")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2, window3],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
        window3.key: CGRect(x: 40, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window3
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.removeWindow(window1.key)
    driver.focusedWindow = window3
    driver.resetRecordedCalls()

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertEqual(driver.focusCalls, [window2.key])
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testUserFocusedOtherWorkspaceWindowStillSwitchesWorkspace() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.resetRecordedCalls()

    driver.focusedWindow = window2
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "2")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertFalse(driver.setFrameCalls.isEmpty)
  }

  func testClosedFocusedWindowWithNoRemainingWindowDoesNotShowGizmoOrSwitch() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.removeWindow(window1.key)
    driver.focusedWindow = window2
    driver.resetRecordedCalls()

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testEmptyActiveWorkspaceDoesNotShowGizmoWithoutTrackedLastFocusedWindow() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.removeWindow(window1.key)
    driver.focusedWindow = window2

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testObservedWindowDestroyedRestoresTopmostWindowInActiveWorkspace() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")
    let window3 = makeWindow(key: "axwn:300")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2, window3],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
        window3.key: CGRect(x: 40, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window3
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.focusedWindow = window2
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.removeWindow(window2.key)
    driver.resetRecordedCalls()

    service.handleObservedWindowDestroyed()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertEqual(driver.focusCalls, [window1.key])
  }

  func testObservedWindowDestroyedDoesNotShowGizmoWhenActiveWorkspaceBecomesEmpty() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.removeWindow(window1.key)

    service.handleObservedWindowDestroyed()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testWorkspaceSyncIgnoresFallbackWindowWhenThereIsNoFocusedWindow() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = nil
    driver.fallbackFocusedWindow = window2

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testWorkspaceSyncIgnoresFocusedWindowThatIsNotManaged() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")
    let unmanagedWindow = makeWindow(key: "axel:500:42")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
        unmanagedWindow.key: CGRect(x: 40, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")
    driver.resetRecordedCalls()

    driver.focusedWindow = unmanagedWindow

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
    XCTAssertTrue(driver.focusCalls.isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  func testFocusWithinWorkspaceUpdatesMRUForSubsequentRestore() {
    let window1 = makeWindow(key: "axwn:100")
    let window2 = makeWindow(key: "axwn:200")
    let window3 = makeWindow(key: "axwn:300")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2, window3],
      frames: [
        window1.key: CGRect(x: 0, y: 0, width: 700, height: 500),
        window2.key: CGRect(x: 20, y: 20, width: 700, height: 500),
        window3.key: CGRect(x: 40, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = window3
    _ = service.moveFocusedWindowToWorkspace("2")

    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.focusedWindow = window2
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.focusedWindow = window1
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.removeWindow(window1.key)
    driver.focusedWindow = window3
    driver.resetRecordedCalls()

    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    XCTAssertEqual(driver.focusCalls, [window2.key])
    XCTAssertEqual(service.state.activeWorkspaceName, "1")
  }

  func testRestoreFromPersistedFramesDoesNotMoveActiveWorkspaceWindowOnStartup() {
    let activeKey = "axwn:100"
    let inactiveKey = "axwn:200"

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [
        makeWindow(key: activeKey),
        makeWindow(key: inactiveKey),
      ],
      frames: [
        activeKey: CGRect(x: 10, y: 10, width: 800, height: 600),
        inactiveKey: CGRect(x: 30, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore(
      loadSnapshot: WorkspaceMappingSnapshot(
        workspaceWindows: [
          "1": [activeKey],
          "2": [inactiveKey],
        ],
        savedFrames: [
          activeKey: PersistedWindowFrame(x: 100, y: 120, width: 900, height: 700),
          inactiveKey: PersistedWindowFrame(x: 220, y: 240, width: 880, height: 660),
        ]
      )
    )

    _ = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    XCTAssertFalse(driver.setFrameCalls.contains(where: { $0.windowKey == activeKey }))
  }

  func testRestoresPersistedActiveWorkspaceOnStartup() {
    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [],
      frames: [:],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore(
      loadSnapshot: WorkspaceMappingSnapshot(
        activeWorkspaceName: "2",
        workspaceWindows: [
          "1": [],
          "2": [],
        ]
      )
    )

    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    XCTAssertEqual(service.state.activeWorkspaceName, "2")
  }

  func testInvalidPersistedActiveWorkspaceFallsBackToFirstConfiguredWorkspace() {
    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [],
      frames: [:],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore(
      loadSnapshot: WorkspaceMappingSnapshot(
        activeWorkspaceName: "3",
        workspaceWindows: [
          "1": [],
          "2": [],
        ]
      )
    )

    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    XCTAssertEqual(service.state.activeWorkspaceName, "1")
  }

  func testSwitchToInactiveWorkspaceRestoresPersistedFrame() {
    let activeKey = "axwn:100"
    let inactiveKey = "axwn:200"
    let inactivePersistedFrame = CGRect(x: 220, y: 240, width: 880, height: 660)

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [
        makeWindow(key: activeKey),
        makeWindow(key: inactiveKey),
      ],
      frames: [
        activeKey: CGRect(x: 10, y: 10, width: 800, height: 600),
        inactiveKey: CGRect(x: 30, y: 40, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore(
      loadSnapshot: WorkspaceMappingSnapshot(
        workspaceWindows: [
          "1": [activeKey],
          "2": [inactiveKey],
        ],
        savedFrames: [
          inactiveKey: PersistedWindowFrame(rect: inactivePersistedFrame)
        ]
      )
    )

    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    driver.resetRecordedCalls()
    _ = service.focusWorkspace("2")

    XCTAssertTrue(
      driver.setFrameCalls.contains(where: {
        $0.windowKey == inactiveKey && $0.frame == inactivePersistedFrame
      })
    )
  }

  func testPersistsSnapshotWhenOnlySavedFramesChanged() throws {
    let key1 = "axwn:100"
    let key2 = "axwn:200"

    let window1 = makeWindow(key: key1)
    let window2 = makeWindow(key: key2)

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        key1: CGRect(x: 0, y: 0, width: 700, height: 500),
        key2: CGRect(x: 200, y: 200, width: 600, height: 400),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore()

    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")

    let workspace1KeysBefore = Set(service.managedWindowKeys(in: "1"))
    let workspace2KeysBefore = Set(service.managedWindowKeys(in: "2"))

    store.savedSnapshots.removeAll()

    _ = service.focusWorkspace("2")

    let persistedSnapshot = try XCTUnwrap(store.savedSnapshots.last)

    XCTAssertEqual(persistedSnapshot.activeWorkspaceName, "2")
    XCTAssertEqual(Set(persistedSnapshot.workspaceWindows["1", default: []]), workspace1KeysBefore)
    XCTAssertEqual(Set(persistedSnapshot.workspaceWindows["2", default: []]), workspace2KeysBefore)
    XCTAssertEqual(Set(persistedSnapshot.savedFrames.keys), [key1])
  }

  func testRestoreAllWindowsClearsSavedFramesAndPersistsSnapshot() throws {
    let key1 = "axwn:100"
    let key2 = "axwn:200"

    let window1 = makeWindow(key: key1)
    let window2 = makeWindow(key: key2)

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [window1, window2],
      frames: [
        key1: CGRect(x: 0, y: 0, width: 700, height: 500),
        key2: CGRect(x: 200, y: 200, width: 600, height: 400),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let store = MockWorkspaceMappingStore()

    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: store
    )

    driver.focusedWindow = window2
    _ = service.moveFocusedWindowToWorkspace("2")

    store.savedSnapshots.removeAll()

    service.restoreAllWindows()

    XCTAssertTrue(service.debugSnapshot().hiddenWindowKeys.isEmpty)

    let persistedSnapshot = try XCTUnwrap(store.savedSnapshots.last)
    XCTAssertTrue(persistedSnapshot.savedFrames.isEmpty)
  }

  func testWorkspaceSwitchLeavesSecondaryDisplayWindowsUnmanaged() {
    let primaryWindow = makeWindow(key: "axwn:100")
    let secondaryWindow = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [primaryWindow, secondaryWindow],
      frames: [
        primaryWindow.key: CGRect(x: 100, y: 100, width: 700, height: 500),
        secondaryWindow.key: CGRect(x: 2200, y: 120, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = primaryWindow
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()
    driver.resetRecordedCalls()

    _ = service.focusWorkspace("2")

    XCTAssertEqual(service.managedWindowKeys(in: "1"), [primaryWindow.key])
    XCTAssertTrue(service.managedWindowKeys(in: "2").isEmpty)
    XCTAssertEqual(driver.setFrameCalls.map(\.windowKey), [primaryWindow.key])
  }

  func testMoveFocusedSecondaryDisplayWindowRemovesItFromTrackedWorkspaces() {
    let primaryWindow = makeWindow(key: "axwn:100")
    let secondaryWindow = makeWindow(key: "axwn:200")

    let driver = MockWorkspaceWindowDriver(
      manageableWindows: [primaryWindow, secondaryWindow],
      frames: [
        primaryWindow.key: CGRect(x: 100, y: 100, width: 700, height: 500),
        secondaryWindow.key: CGRect(x: 2200, y: 120, width: 700, height: 500),
      ],
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
    )
    let service = VirtualWorkspaceService(
      driver: driver,
      initialConfig: makeWorkspaceConfig(),
      workspaceMappingStore: MockWorkspaceMappingStore()
    )

    driver.focusedWindow = primaryWindow
    service.synchronizeActiveWorkspaceToFocusedWindowIfNeeded()

    driver.focusedWindow = secondaryWindow
    driver.resetRecordedCalls()

    let result = service.moveFocusedWindowToWorkspace("2")

    XCTAssertEqual(result, .success(()))
    XCTAssertEqual(service.managedWindowKeys(in: "1"), [primaryWindow.key])
    XCTAssertTrue(service.managedWindowKeys(in: "2").isEmpty)
    XCTAssertTrue(driver.setFrameCalls.isEmpty)
  }

  private func makeWorkspaceConfig() -> WorkspaceConfig {
    WorkspaceConfig(
      enabled: true,
      names: ["1", "2"],
      hideStrategy: .cornerOffscreen
    )
  }

  private func makeWindow(key: WindowKey) -> ManagedWindowRef {
    ManagedWindowRef(
      key: key,
      element: nil,
      appName: "Test App",
      title: key
    )
  }
}

@MainActor
private final class MockWorkspaceWindowDriver: WorkspaceWindowDriver {
  struct SetFrameCall {
    let windowKey: WindowKey
    let frame: CGRect
  }

  var accessibilityGranted = true
  var focusedWindow: ManagedWindowRef?
  var fallbackFocusedWindow: ManagedWindowRef?
  var manageableWindows: [ManagedWindowRef]
  var frames: [WindowKey: CGRect]
  var visibleFrame: CGRect?

  private(set) var setFrameCalls: [SetFrameCall] = []
  private(set) var focusCalls: [WindowKey] = []

  init(
    manageableWindows: [ManagedWindowRef],
    frames: [WindowKey: CGRect],
    visibleFrame: CGRect?
  ) {
    self.manageableWindows = manageableWindows
    self.frames = frames
    self.visibleFrame = visibleFrame
    self.focusedWindow = manageableWindows.first
  }

  func isAccessibilityGranted() -> Bool {
    accessibilityGranted
  }

  func resolveFocusedWindow(
    preferredWindow: AXUIElement?,
    allowFallbackWindow: Bool
  ) -> ManagedWindowRef? {
    focusedWindow ?? (allowFallbackWindow ? fallbackFocusedWindow : nil)
  }

  func allManageableWindows() -> [ManagedWindowRef] {
    manageableWindows
  }

  func frame(for window: ManagedWindowRef) -> CGRect? {
    frames[window.key]
  }

  func setFrame(_ frame: CGRect, for window: ManagedWindowRef) -> Bool {
    setFrameCalls.append(SetFrameCall(windowKey: window.key, frame: frame))
    frames[window.key] = frame
    return true
  }

  func focus(_ window: ManagedWindowRef) -> Bool {
    focusCalls.append(window.key)
    focusedWindow = window
    true
  }

  func isWindowAlive(_ window: ManagedWindowRef) -> Bool {
    frames[window.key] != nil
  }

  func singleMonitorVisibleFrame() -> CGRect? {
    visibleFrame
  }

  func resetRecordedCalls() {
    setFrameCalls.removeAll()
    focusCalls.removeAll()
  }

  func removeWindow(_ key: WindowKey) {
    frames.removeValue(forKey: key)
    manageableWindows.removeAll { $0.key == key }
    if focusedWindow?.key == key {
      focusedWindow = nil
    }
  }
}

private final class MockWorkspaceMappingStore: WorkspaceMappingStore {
  var loadSnapshot: WorkspaceMappingSnapshot?
  var savedSnapshots: [WorkspaceMappingSnapshot] = []

  init(loadSnapshot: WorkspaceMappingSnapshot? = nil) {
    self.loadSnapshot = loadSnapshot
  }

  func load() -> WorkspaceMappingSnapshot? {
    loadSnapshot
  }

  func save(_ snapshot: WorkspaceMappingSnapshot) {
    savedSnapshots.append(snapshot)
    loadSnapshot = snapshot
  }
}
