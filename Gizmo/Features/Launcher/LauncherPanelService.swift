import AppKit
import SwiftUI

@MainActor
final class LauncherPanelService: NSObject, NSWindowDelegate {
  private enum PanelLayout {
    static let width: CGFloat = 680
    static let height: CGFloat = 320
  }

  // MARK: - Properties

  private let windowManagerService: WindowManagerService
  private let virtualWorkspaceService: VirtualWorkspaceService
  private let accessibilityPermissionService: AccessibilityPermissionService
  private let configStore: ConfigStore

  var onOpenMainWindowRequest: ((_ targetCenter: CGPoint?) -> Void)?

  private var panel: LauncherPanel?
  private var panelHostingController: NSHostingController<LauncherInputView>?
  private var previousInputSourceID: String?
  private var focusedWindowBeforePanelOpen: AXUIElement?
  private var commands: [LauncherCommand]

  // MARK: - Initialization

  init(
    windowManagerService: WindowManagerService,
    virtualWorkspaceService: VirtualWorkspaceService,
    accessibilityPermissionService: AccessibilityPermissionService,
    configStore: ConfigStore
  ) {
    self.windowManagerService = windowManagerService
    self.virtualWorkspaceService = virtualWorkspaceService
    self.accessibilityPermissionService = accessibilityPermissionService
    self.configStore = configStore
    self.commands = LauncherCommand.makeAll(workspaceNames: virtualWorkspaceService.state.workspaceNames)
    super.init()
  }

  // MARK: - Panel Control

  func togglePanel() {
    if panel?.isVisible == true {
      hidePanel()
    } else {
      showPanel()
    }
  }

  func hidePanel() {
    restoreInputSourceIfNeeded()
    panel?.orderOut(nil)
    focusedWindowBeforePanelOpen = nil
  }

  func showPanel() {
    if panel == nil {
      panel = createPanel()
    } else {
      refreshPanelContent()
    }

    guard let panel else { return }

    focusedWindowBeforePanelOpen = AXUIElement.focusedWindowElement()
    activateEnglishInputSourceIfNeeded()
    panel.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
    positionPanelOnActiveScreen(panel)
    panel.makeKeyAndOrderFront(nil)

    NotificationCenter.default.post(
      name: .launcherPanelDidOpen,
      object: nil
    )
  }

  func updateWorkspaceCommands(workspaceNames: [String]) {
    commands = LauncherCommand.makeAll(workspaceNames: workspaceNames)
    refreshPanelContent()
  }

  // MARK: - Private

  private func activateEnglishInputSourceIfNeeded() {
    guard configStore.active.launcher.forceEnglishInputSource else {
      previousInputSourceID = nil
      return
    }

    previousInputSourceID = InputSourceService.switchToEnglishInputSource()
  }

  private func restoreInputSourceIfNeeded() {
    guard let previousInputSourceID else { return }
    InputSourceService.selectInputSource(withID: previousInputSourceID)
    self.previousInputSourceID = nil
  }

  private func positionPanelOnActiveScreen(_ panel: NSPanel) {
    let screenPreference = configStore.active.launcher.display
    let targetScreen =
      screenPreference.targetScreen
      ?? NSScreen.main
      ?? NSScreen.screens.first

    guard let targetScreen else { return }

    let screenFrame = targetScreen.frame
    let panelSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
    let frame = NSRect(
      x: floor(screenFrame.midX - (panelSize.width / 2)),
      y: floor(screenFrame.midY - (panelSize.height / 2)),
      width: panelSize.width,
      height: panelSize.height
    )

    panel.setFrame(frame, display: false)
  }

  private func createPanel() -> LauncherPanel {
    let hostingController = makePanelHostingController()
    panelHostingController = hostingController

    let panel = LauncherPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: PanelLayout.width,
        height: PanelLayout.height
      ),
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [
      .fullScreenAuxiliary,
      .transient,
      .moveToActiveSpace,
    ]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.delegate = self
    panel.contentViewController = hostingController

    return panel
  }

  private func makePanelHostingController() -> NSHostingController<LauncherInputView> {
    NSHostingController(rootView: makeLauncherInputView())
  }

  private func makeLauncherInputView() -> LauncherInputView {
    LauncherInputView(
      commands: commands,
      onClose: { [weak self] in
        self?.hidePanel()
      },
      onExecuteCommand: { [weak self] command in
        guard let self else { return .failure(.windowManager(.applyFailed)) }
        return self.execute(command)
      },
      onOpenAccessibilitySettings: { [weak self] in
        self?.accessibilityPermissionService.openSystemSettings()
      },
      onOpenMainWindow: { [weak self] in
        self?.openMainWindowFromLauncher()
      }
    )
  }

  private func refreshPanelContent() {
    guard let panelHostingController else { return }
    panelHostingController.rootView = makeLauncherInputView()
  }

  private func execute(_ command: LauncherCommand) -> Result<Void, LauncherCommandError> {
    let result: Result<Void, LauncherCommandError>

    switch command.action {
    case .tile(let tileAction):
      result = mapWindowManagerResult(
        windowManagerService.execute(
          tileAction,
          preferredWindowElement: focusedWindowBeforePanelOpen
        )
      )
    case .workspaceFocus(let workspaceName):
      result = mapWorkspaceResult(
        virtualWorkspaceService.focusWorkspace(workspaceName)
      )
    case .workspaceBackAndForth:
      result = mapWorkspaceResult(
        virtualWorkspaceService.focusPreviousWorkspace()
      )
    case .moveFocusedWindowToWorkspace(let workspaceName):
      result = mapWorkspaceResult(
        virtualWorkspaceService.moveFocusedWindowToWorkspace(
          workspaceName,
          preferredWindowElement: focusedWindowBeforePanelOpen
        )
      )
    }

    if case .success = result {
      focusedWindowBeforePanelOpen = nil
    }

    return result
  }

  private func mapWindowManagerResult(
    _ result: Result<Void, WindowManagerError>
  ) -> Result<Void, LauncherCommandError> {
    switch result {
    case .success:
      return .success(())
    case .failure(let error):
      return .failure(.windowManager(error))
    }
  }

  private func mapWorkspaceResult(
    _ result: Result<Void, WorkspaceError>
  ) -> Result<Void, LauncherCommandError> {
    switch result {
    case .success:
      return .success(())
    case .failure(let error):
      return .failure(.workspace(error))
    }
  }

  // MARK: - NSWindowDelegate

  func windowDidResignKey(_ notification: Notification) {
    hidePanel()
  }

  private func openMainWindowFromLauncher() {
    let targetCenter = launcherDisplayCenter()
    hidePanel()

    guard let candidate = existingMainWindow() else {
      onOpenMainWindowRequest?(targetCenter)
      return
    }

    centerWindow(candidate, at: targetCenter)

    if candidate.isMiniaturized {
      candidate.deminiaturize(nil)
    }

    NSApplication.shared.activate(ignoringOtherApps: true)
    candidate.makeKeyAndOrderFront(nil)
  }

  private func launcherDisplayCenter() -> CGPoint? {
    if let panel, let screen = panel.screen {
      return screen.frame.center
    }

    if
      let panelCenter = panel?.frame.center,
      let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
    {
      return containingScreen.frame.center
    }

    return NSScreen.main?.frame.center ?? NSScreen.screens.first?.frame.center
  }

  private func existingMainWindow() -> NSWindow? {
    if let taggedCandidate = NSApplication.shared.orderedWindows.first(where: isTaggedMainWindow(_:)) {
      return taggedCandidate
    }

    if let taggedCandidate = NSApplication.shared.windows.first(where: isTaggedMainWindow(_:)) {
      return taggedCandidate
    }

    if let orderedCandidate = NSApplication.shared.orderedWindows.first(where: isMainWindowCandidate(_:)) {
      return orderedCandidate
    }

    return NSApplication.shared.windows.first(where: isMainWindowCandidate(_:))
  }

  private func isTaggedMainWindow(_ window: NSWindow) -> Bool {
    window.identifier == MainWindowIdentity.identifier
  }

  private func isMainWindowCandidate(_ window: NSWindow) -> Bool {
    if window === panel { return false }
    if window is NSPanel { return false }
    if !window.canBecomeMain { return false }

    return true
  }

  private func centerWindow(_ window: NSWindow, at targetCenter: CGPoint?) {
    guard let targetCenter else { return }

    var frame = window.frame
    frame.origin.x = floor(targetCenter.x - (frame.width / 2))
    frame.origin.y = floor(targetCenter.y - (frame.height / 2))
    window.setFrameOrigin(frame.origin)
  }
}

private final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

extension Notification.Name {
  static let launcherPanelDidOpen = Notification.Name("launcherPanelDidOpen")
}

extension LauncherDisplay {
  var targetScreen: NSScreen? {
    switch self {
    case .primary:
      return NSScreen.screens.first
    case .mouse:
      let mouseLocation = NSEvent.mouseLocation
      return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    case .activeWindow:
      return NSScreen.main
    }
  }
}

private extension CGRect {
  var center: CGPoint {
    CGPoint(x: midX, y: midY)
  }
}
