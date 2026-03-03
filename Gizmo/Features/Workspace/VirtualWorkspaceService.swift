import AppKit
import ApplicationServices
import Observation

typealias WindowKey = String

struct ManagedWindowRef: Hashable {
  let key: WindowKey
  let element: AXUIElement?
  let appName: String?
  let title: String?

  init(
    key: WindowKey,
    element: AXUIElement?,
    appName: String? = nil,
    title: String? = nil
  ) {
    self.key = key
    self.element = element
    self.appName = appName
    self.title = title
  }

  var displayName: String {
    let trimmedAppName = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if !trimmedAppName.isEmpty && !trimmedTitle.isEmpty {
      return "\(trimmedAppName) - \(trimmedTitle)"
    }
    if !trimmedAppName.isEmpty {
      return trimmedAppName
    }
    if !trimmedTitle.isEmpty {
      return trimmedTitle
    }
    return key
  }

  static func == (lhs: ManagedWindowRef, rhs: ManagedWindowRef) -> Bool {
    lhs.key == rhs.key
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key)
  }
}

enum WorkspaceError: Error, Equatable, LocalizedError {
  case permissionDenied
  case workspaceDisabled
  case invalidWorkspace
  case noFocusedWindow
  case noUsableScreen
  case applyFailed

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return String(localized: "Accessibility permission is required.")
    case .workspaceDisabled:
      return String(localized: "Workspace feature is disabled in config.")
    case .invalidWorkspace:
      return String(localized: "Invalid workspace.")
    case .noFocusedWindow:
      return String(localized: "No focused window.")
    case .noUsableScreen:
      return String(localized: "No usable screen found.")
    case .applyFailed:
      return String(localized: "Failed to move window.")
    }
  }
}

struct VirtualWorkspaceState: Equatable {
  let enabled: Bool
  let workspaceNames: [String]
  let activeWorkspaceName: String
  let previousWorkspaceName: String?
}

struct VirtualWorkspaceDebugSnapshot: Equatable {
  let state: VirtualWorkspaceState
  let workspaceWindows: [String: [WindowKey]]
  let windowDisplayNames: [WindowKey: String]
  let hiddenWindowKeys: Set<WindowKey>

  var managedWindowKeys: [WindowKey] {
    var seen: Set<WindowKey> = []
    var ordered: [WindowKey] = []
    for workspaceName in state.workspaceNames {
      for key in workspaceWindows[workspaceName, default: []] {
        guard seen.insert(key).inserted else { continue }
        ordered.append(key)
      }
    }
    return ordered
  }
}

protocol WorkspaceWindowDriver {
  @MainActor func isAccessibilityGranted() -> Bool
  @MainActor func resolveFocusedWindow(preferredWindow: AXUIElement?) -> ManagedWindowRef?
  @MainActor func frame(for window: ManagedWindowRef) -> CGRect?
  @MainActor func setFrame(_ frame: CGRect, for window: ManagedWindowRef) -> Bool
  @MainActor func isWindowAlive(_ window: ManagedWindowRef) -> Bool
  @MainActor func singleMonitorVisibleFrame() -> CGRect?
}

@MainActor
final class LiveWorkspaceWindowDriver: WorkspaceWindowDriver {
  private let permissionService: AccessibilityPermissionService

  init(permissionService: AccessibilityPermissionService) {
    self.permissionService = permissionService
  }

  func isAccessibilityGranted() -> Bool {
    permissionService.refresh()
    return permissionService.isGranted
  }

  func resolveFocusedWindow(preferredWindow: AXUIElement?) -> ManagedWindowRef? {
    if let preferredWindow {
      let preferredRef = makeManagedWindowRef(from: preferredWindow)
      if isWindowAlive(preferredRef) {
        return preferredRef
      }
    }

    guard let focusedWindow = AXUIElement.focusedWindowElement() else {
      return nil
    }
    let focusedRef = makeManagedWindowRef(from: focusedWindow)
    return isWindowAlive(focusedRef) ? focusedRef : nil
  }

  func frame(for window: ManagedWindowRef) -> CGRect? {
    guard let element = window.element else { return nil }
    guard let frame = element.frame, !frame.isNull else { return nil }
    return frame.screenFlipped
  }

  func setFrame(_ frame: CGRect, for window: ManagedWindowRef) -> Bool {
    guard let element = window.element else { return false }
    return element.setFrame(frame.screenFlipped)
  }

  func isWindowAlive(_ window: ManagedWindowRef) -> Bool {
    frame(for: window) != nil
  }

  func singleMonitorVisibleFrame() -> CGRect? {
    (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
  }

  private func makeManagedWindowRef(from element: AXUIElement) -> ManagedWindowRef {
    ManagedWindowRef(
      key: windowKey(for: element),
      element: element,
      appName: appName(for: element),
      title: title(for: element)
    )
  }

  private func appName(for element: AXUIElement) -> String? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return nil }
    return NSRunningApplication(processIdentifier: pid)?.localizedName
  }

  private func title(for element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success
    else {
      return nil
    }
    return value as? String
  }

  private func windowKey(for element: AXUIElement) -> WindowKey {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success,
      let windowNumber = value as? NSNumber
    {
      return "axwn:\(windowNumber.intValue)"
    }

    let pointer = Unmanaged.passUnretained(element).toOpaque()
    return "axptr:\(Int(bitPattern: pointer))"
  }
}

@Observable
@MainActor
final class VirtualWorkspaceService {
  private let driver: any WorkspaceWindowDriver

  private(set) var enabled: Bool
  private(set) var workspaceNames: [String]
  private(set) var activeWorkspaceName: String
  private(set) var previousWorkspaceName: String?

  private var workspaceWindows: [String: [ManagedWindowRef]]
  private var savedFrames: [WindowKey: CGRect] = [:]

  var onStateDidChange: ((VirtualWorkspaceState) -> Void)?

  convenience init(
    permissionService: AccessibilityPermissionService,
    initialConfig: WorkspaceConfig
  ) {
    self.init(
      driver: LiveWorkspaceWindowDriver(permissionService: permissionService),
      initialConfig: initialConfig
    )
  }

  init(
    driver: any WorkspaceWindowDriver,
    initialConfig: WorkspaceConfig
  ) {
    self.driver = driver

    let normalizedWorkspaceNames = Self.normalizeWorkspaceNames(initialConfig.names)
    self.enabled = initialConfig.enabled
    self.workspaceNames = normalizedWorkspaceNames
    self.activeWorkspaceName = normalizedWorkspaceNames.first ?? WorkspaceConfig.defaultNames[0]
    self.previousWorkspaceName = nil
    self.workspaceWindows = Dictionary(
      uniqueKeysWithValues: normalizedWorkspaceNames.map { ($0, []) }
    )
  }

  var state: VirtualWorkspaceState {
    VirtualWorkspaceState(
      enabled: enabled,
      workspaceNames: workspaceNames,
      activeWorkspaceName: activeWorkspaceName,
      previousWorkspaceName: previousWorkspaceName
    )
  }

  func debugSnapshot() -> VirtualWorkspaceDebugSnapshot {
    let mappedWorkspaceWindows = Dictionary(
      uniqueKeysWithValues: workspaceNames.map { workspaceName in
        (
          workspaceName,
          workspaceWindows[workspaceName, default: []].map(\.key)
        )
      }
    )
    var windowDisplayNames: [WindowKey: String] = [:]
    for window in allManagedWindows {
      windowDisplayNames[window.key] = window.displayName
    }

    return VirtualWorkspaceDebugSnapshot(
      state: state,
      workspaceWindows: mappedWorkspaceWindows,
      windowDisplayNames: windowDisplayNames,
      hiddenWindowKeys: Set(savedFrames.keys)
    )
  }

  func apply(config: WorkspaceConfig) {
    let wasEnabled = enabled

    let normalizedWorkspaceNames = Self.normalizeWorkspaceNames(config.names)
    workspaceNames = normalizedWorkspaceNames
    enabled = config.enabled

    let fallbackWorkspace = normalizedWorkspaceNames.first ?? WorkspaceConfig.defaultNames[0]

    var remappedWorkspaceWindows: [String: [ManagedWindowRef]] =
      Dictionary(uniqueKeysWithValues: normalizedWorkspaceNames.map { ($0, []) })

    for (workspaceName, windows) in workspaceWindows {
      let targetWorkspaceName = normalizedWorkspaceNames.contains(workspaceName)
        ? workspaceName
        : fallbackWorkspace
      for window in windows {
        Self.appendUnique(window, to: &remappedWorkspaceWindows[targetWorkspaceName, default: []])
      }
    }
    workspaceWindows = remappedWorkspaceWindows

    if !workspaceNames.contains(activeWorkspaceName) {
      activeWorkspaceName = fallbackWorkspace
    }
    if let previousWorkspaceName, !workspaceNames.contains(previousWorkspaceName) {
      self.previousWorkspaceName = nil
    }

    pruneDeadWindows()

    if wasEnabled && !enabled {
      restoreAllWindows()
    } else if enabled && driver.isAccessibilityGranted() {
      _ = reconcileVisibility()
    }

    notifyStateDidChange()
  }

  func focusWorkspace(_ workspaceName: String) -> Result<Void, WorkspaceError> {
    guard enabled else { return .failure(.workspaceDisabled) }
    guard workspaceNames.contains(workspaceName) else { return .failure(.invalidWorkspace) }
    guard driver.isAccessibilityGranted() else { return .failure(.permissionDenied) }

    pruneDeadWindows()

    guard workspaceName != activeWorkspaceName else { return .success(()) }

    let currentWorkspace = activeWorkspaceName
    var hasApplyFailure = false

    for window in workspaceWindows[currentWorkspace, default: []] {
      if !hide(window) {
        hasApplyFailure = true
      }
    }

    for window in workspaceWindows[workspaceName, default: []] {
      if !unhide(window) {
        hasApplyFailure = true
      }
    }

    previousWorkspaceName = currentWorkspace
    activeWorkspaceName = workspaceName
    notifyStateDidChange()

    return hasApplyFailure ? .failure(.applyFailed) : .success(())
  }

  func focusPreviousWorkspace() -> Result<Void, WorkspaceError> {
    guard let previousWorkspaceName,
      workspaceNames.contains(previousWorkspaceName)
    else {
      return .success(())
    }

    return focusWorkspace(previousWorkspaceName)
  }

  func moveFocusedWindowToWorkspace(
    _ workspaceName: String,
    preferredWindowElement: AXUIElement? = nil
  ) -> Result<Void, WorkspaceError> {
    guard enabled else { return .failure(.workspaceDisabled) }
    guard workspaceNames.contains(workspaceName) else { return .failure(.invalidWorkspace) }
    guard driver.isAccessibilityGranted() else { return .failure(.permissionDenied) }

    pruneDeadWindows()

    guard let focusedWindow = driver.resolveFocusedWindow(preferredWindow: preferredWindowElement) else {
      return .failure(.noFocusedWindow)
    }

    removeWindowFromAllWorkspaces(focusedWindow)
    Self.appendUnique(focusedWindow, to: &workspaceWindows[workspaceName, default: []])

    let didApply = if workspaceName == activeWorkspaceName {
      unhide(focusedWindow)
    } else {
      hide(focusedWindow)
    }

    notifyStateDidChange()
    return didApply ? .success(()) : .failure(.applyFailed)
  }

  func restoreAllWindows() {
    pruneDeadWindows()

    let visibleFrame = driver.singleMonitorVisibleFrame()
    let windows = allManagedWindows

    for window in windows {
      guard let savedFrame = savedFrames[window.key] else { continue }

      if driver.setFrame(savedFrame, for: window) {
        savedFrames.removeValue(forKey: window.key)
        continue
      }

      guard let visibleFrame,
        let currentFrame = driver.frame(for: window)
      else {
        continue
      }

      let fallbackFrame = Self.centeredFrame(
        for: currentFrame.size,
        in: visibleFrame
      )
      if driver.setFrame(fallbackFrame, for: window) {
        savedFrames.removeValue(forKey: window.key)
      }
    }
  }

  func managedWindowKeys(in workspaceName: String) -> [WindowKey] {
    workspaceWindows[workspaceName, default: []].map(\.key)
  }

  private var allManagedWindows: [ManagedWindowRef] {
    var unique: [WindowKey: ManagedWindowRef] = [:]
    for windows in workspaceWindows.values {
      for window in windows {
        unique[window.key] = window
      }
    }
    return Array(unique.values)
  }

  private func reconcileVisibility() -> Bool {
    var success = true
    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      if workspaceName == activeWorkspaceName {
        for window in windows where !unhide(window) {
          success = false
        }
      } else {
        for window in windows where !hide(window) {
          success = false
        }
      }
    }
    return success
  }

  private func hide(_ window: ManagedWindowRef) -> Bool {
    guard let currentFrame = driver.frame(for: window) else {
      return false
    }
    guard let visibleFrame = driver.singleMonitorVisibleFrame() else {
      return false
    }

    if savedFrames[window.key] == nil {
      savedFrames[window.key] = currentFrame
    }

    let hiddenFrame = Self.hiddenFrame(for: currentFrame, in: visibleFrame)
    return driver.setFrame(hiddenFrame, for: window)
  }

  private func unhide(_ window: ManagedWindowRef) -> Bool {
    guard let savedFrame = savedFrames[window.key] else {
      return true
    }

    guard driver.setFrame(savedFrame, for: window) else {
      return false
    }

    savedFrames.removeValue(forKey: window.key)
    return true
  }

  private func pruneDeadWindows() {
    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      var unique: [WindowKey: ManagedWindowRef] = [:]
      for window in windows where driver.isWindowAlive(window) {
        unique[window.key] = window
      }
      workspaceWindows[workspaceName] = Array(unique.values)
    }

    let aliveKeys = Set(allManagedWindows.map(\.key))
    savedFrames = savedFrames.filter { aliveKeys.contains($0.key) }
  }

  private func removeWindowFromAllWorkspaces(_ target: ManagedWindowRef) {
    for workspaceName in workspaceNames {
      workspaceWindows[workspaceName, default: []].removeAll { $0.key == target.key }
    }
  }

  private func notifyStateDidChange() {
    onStateDidChange?(state)
  }

  private static func appendUnique(_ window: ManagedWindowRef, to windows: inout [ManagedWindowRef]) {
    guard !windows.contains(where: { $0.key == window.key }) else { return }
    windows.append(window)
  }

  private static func normalizeWorkspaceNames(_ names: [String]) -> [String] {
    var normalized: [String] = []
    var seen: Set<String> = []

    for rawName in names {
      let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { continue }
      guard seen.insert(trimmedName).inserted else { continue }
      normalized.append(trimmedName)
    }

    return normalized.isEmpty ? WorkspaceConfig.defaultNames : normalized
  }

  private static func hiddenFrame(for frame: CGRect, in visibleFrame: CGRect) -> CGRect {
    CGRect(
      x: visibleFrame.maxX + 2,
      y: visibleFrame.minY - frame.height - 2,
      width: max(1, frame.width),
      height: max(1, frame.height)
    )
  }

  private static func centeredFrame(for size: CGSize, in visibleFrame: CGRect) -> CGRect {
    let width = min(max(1, size.width), visibleFrame.width)
    let height = min(max(1, size.height), visibleFrame.height)

    return CGRect(
      x: floor(visibleFrame.midX - (width / 2)),
      y: floor(visibleFrame.midY - (height / 2)),
      width: width,
      height: height
    )
  }
}
