import AppKit
import ApplicationServices
import Observation

typealias WindowKey = String

struct ManagedWindowRef: Hashable {
  let key: WindowKey
  let element: AXUIElement?
  let processIdentifier: pid_t?
  let appName: String?
  let title: String?

  init(
    key: WindowKey,
    element: AXUIElement?,
    processIdentifier: pid_t? = nil,
    appName: String? = nil,
    title: String? = nil
  ) {
    self.key = key
    self.element = element
    self.processIdentifier = processIdentifier
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
  let displayStates: [WorkspaceDisplayRole: WorkspaceDisplayState]
}

struct WorkspaceDisplayState: Equatable {
  let workspaceNames: [String]
  let activeWorkspaceName: String
  let previousWorkspaceName: String?
  let appNamesByWorkspace: [String: [String]]
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
  @MainActor func resolveFocusedWindow(
    preferredWindow: AXUIElement?,
    allowFallbackWindow: Bool
  ) -> ManagedWindowRef?
  @MainActor func allManageableWindows() -> [ManagedWindowRef]
  @MainActor func frame(for window: ManagedWindowRef) -> CGRect?
  @MainActor func setFrame(_ frame: CGRect, for window: ManagedWindowRef) -> Bool
  @MainActor func focus(_ window: ManagedWindowRef) -> Bool
  @MainActor func isWindowAlive(_ window: ManagedWindowRef) -> Bool
  @MainActor func screenFrame() -> CGRect?
  @MainActor func visibleFrame() -> CGRect?
}

@MainActor
final class LiveWorkspaceWindowDriver: WorkspaceWindowDriver {
  private let permissionService: AccessibilityPermissionService
  private let fallbackWindowElementProvider: @MainActor () -> AXUIElement?

  init(
    permissionService: AccessibilityPermissionService,
    fallbackWindowElementProvider: @escaping @MainActor () -> AXUIElement? = { nil }
  ) {
    self.permissionService = permissionService
    self.fallbackWindowElementProvider = fallbackWindowElementProvider
  }

  func isAccessibilityGranted() -> Bool {
    permissionService.refresh()
    return permissionService.isGranted
  }

  func resolveFocusedWindow(
    preferredWindow: AXUIElement?,
    allowFallbackWindow: Bool
  ) -> ManagedWindowRef? {
    if let preferredRef = validatedManagedWindowRef(from: preferredWindow) {
      return preferredRef
    }

    let focusedWindowRef = validatedManagedWindowRef(
      from: AXUIElement.focusedWindowElement()
    )

    if let focusedWindowRef, !belongsToCurrentProcess(focusedWindowRef) {
      return focusedWindowRef
    }

    guard allowFallbackWindow else {
      return nil
    }

    if let fallbackRef = validatedManagedWindowRef(from: fallbackWindowElementProvider()) {
      return fallbackRef
    }

    return focusedWindowRef
  }

  func allManageableWindows() -> [ManagedWindowRef] {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let candidateWindowNumbers = currentWindowNumbers(excludingPID: currentPID)
    var mapped: [WindowKey: ManagedWindowRef] = [:]

    for app in NSWorkspace.shared.runningApplications {
      guard app.processIdentifier != currentPID else { continue }
      guard app.activationPolicy == .regular else { continue }

      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      guard let appWindows = axWindows(for: appElement) else { continue }

      for windowElement in appWindows {
        let windowRef = makeManagedWindowRef(from: windowElement)
        guard isManageable(windowRef, candidateWindowNumbers: candidateWindowNumbers) else {
          continue
        }
        mapped[windowRef.key] = windowRef
      }
    }

    return Array(mapped.values)
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

  func focus(_ window: ManagedWindowRef) -> Bool {
    guard let element = window.element else { return false }

    var pid: pid_t = 0
    let didResolvePID = AXUIElementGetPid(element, &pid) == .success
    let didActivate = if didResolvePID {
      NSRunningApplication(processIdentifier: pid)?.activate(
        options: [.activateAllWindows]
      ) ?? false
    } else {
      false
    }

    let didRaise = AXUIElementPerformAction(
      element,
      kAXRaiseAction as CFString
    ) == .success
    let didSetMain = AXUIElementSetAttributeValue(
      element,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    ) == .success
    let didSetFocused = AXUIElementSetAttributeValue(
      element,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    ) == .success

    return didActivate || didRaise || didSetMain || didSetFocused
  }

  func isWindowAlive(_ window: ManagedWindowRef) -> Bool {
    frame(for: window) != nil
  }

  func screenFrame() -> CGRect? {
    primaryScreen()?.frame
  }

  func visibleFrame() -> CGRect? {
    primaryScreen()?.visibleFrame
  }

  private func currentWindowNumbers(excludingPID excludedPID: pid_t) -> Set<Int> {
    let options: CGWindowListOption = [.excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else {
      return []
    }

    var numbers: Set<Int> = []
    for window in windows {
      let layer = intValue(for: "kCGWindowLayer", in: window)
      guard layer == 0 else { continue }

      let ownerPID = pid_t(intValue(for: "kCGWindowOwnerPID", in: window))
      guard ownerPID != excludedPID else { continue }

      let number = intValue(for: "kCGWindowNumber", in: window)
      guard number > 0 else { continue }

      numbers.insert(number)
    }

    return numbers
  }

  private func primaryScreen() -> NSScreen? {
    NSScreen.screens.first
  }

  private func axWindows(for appElement: AXUIElement) -> [AXUIElement]? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success
    else {
      return nil
    }

    return value as? [AXUIElement]
  }

  private func isManageable(
    _ window: ManagedWindowRef,
    candidateWindowNumbers: Set<Int>
  ) -> Bool {
    guard let frame = frame(for: window), !frame.isNull else {
      return false
    }
    guard frame.width >= 1, frame.height >= 1 else {
      return false
    }

    if isFinderDesktopWindow(window) {
      return false
    }

    if let windowNumber = windowNumber(from: window.key) {
      return candidateWindowNumbers.contains(windowNumber)
    }

    return true
  }

  private func windowNumber(from key: WindowKey) -> Int? {
    guard key.hasPrefix("axwn:") else { return nil }
    return Int(key.dropFirst("axwn:".count))
  }

  private func intValue(for key: String, in dict: [String: Any]) -> Int {
    if let value = dict[key] as? Int { return value }
    if let value = dict[key] as? NSNumber { return value.intValue }
    return 0
  }

  private func makeManagedWindowRef(from element: AXUIElement) -> ManagedWindowRef {
    ManagedWindowRef(
      key: windowKey(for: element),
      element: element,
      processIdentifier: processIdentifier(for: element),
      appName: appName(for: element),
      title: title(for: element)
    )
  }

  private func validatedManagedWindowRef(from element: AXUIElement?) -> ManagedWindowRef? {
    guard let element else { return nil }
    let windowRef = makeManagedWindowRef(from: element)
    return isWindowAlive(windowRef) ? windowRef : nil
  }

  private func isFinderDesktopWindow(_ window: ManagedWindowRef) -> Bool {
    guard windowNumber(from: window.key) == nil else {
      return false
    }

    let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard title.isEmpty else {
      return false
    }

    guard let element = window.element else {
      return false
    }

    return bundleIdentifier(for: element) == "com.apple.finder"
  }

  private func belongsToCurrentProcess(_ window: ManagedWindowRef) -> Bool {
    window.processIdentifier == ProcessInfo.processInfo.processIdentifier
  }

  private func processIdentifier(for element: AXUIElement) -> pid_t? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return nil }
    return pid
  }

  private func bundleIdentifier(for element: AXUIElement) -> String? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else {
      return nil
    }

    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
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

    var pid: pid_t = 0
    _ = AXUIElementGetPid(element, &pid)
    let elementHash = CFHash(element)
    return "axel:\(pid):\(elementHash)"
  }
}

@Observable
@MainActor
final class VirtualWorkspaceService {
  private let driver: any WorkspaceWindowDriver
  private let workspaceMappingStore: any WorkspaceMappingStore

  private(set) var enabled: Bool
  private(set) var workspaceNames: [String]
  private(set) var activeWorkspaceName: String
  private(set) var previousWorkspaceName: String?

  private var activeWorkspaceNamesByDisplay: [WorkspaceDisplayRole: String]
  private var previousWorkspaceNamesByDisplay: [WorkspaceDisplayRole: String]
  private var workspaceWindows: [String: [ManagedWindowRef]]
  private var savedFrames: [WindowKey: CGRect] = [:]
  private var pendingPersistedWorkspaceWindowKeys: [String: [WindowKey]]
  private var pendingPersistedSavedFrames: [WindowKey: PersistedWindowFrame]
  private var lastPersistedWorkspaceSnapshot: WorkspaceMappingSnapshot?
  private var lastFocusedManagedWindowKeyByDisplay: [WorkspaceDisplayRole: WindowKey]
  private var lastFocusedManagedWindowWorkspaceNameByDisplay: [WorkspaceDisplayRole: String]

  var onStateDidChange: ((VirtualWorkspaceState) -> Void)?

  convenience init(
    permissionService: AccessibilityPermissionService,
    initialConfig: WorkspaceConfig,
    workspaceMappingStore: (any WorkspaceMappingStore)? = nil,
    fallbackWindowElementProvider: (@MainActor () -> AXUIElement?)? = nil
  ) {
    self.init(
      driver: LiveWorkspaceWindowDriver(
        permissionService: permissionService,
        fallbackWindowElementProvider: fallbackWindowElementProvider ?? { nil }
      ),
      initialConfig: initialConfig,
      workspaceMappingStore: workspaceMappingStore
    )
  }

  init(
    driver: any WorkspaceWindowDriver,
    initialConfig: WorkspaceConfig,
    workspaceMappingStore: (any WorkspaceMappingStore)? = nil
  ) {
    self.driver = driver
    self.workspaceMappingStore = workspaceMappingStore ?? FileWorkspaceMappingStore()

    let persistedSnapshot = self.workspaceMappingStore.load()

    let normalizedWorkspaceNames = Self.normalizeWorkspaceNames(
      initialConfig.primaryNames,
      fallback: WorkspaceConfig.defaultNames
    )

    self.enabled = initialConfig.enabled
    self.workspaceNames = normalizedWorkspaceNames
    self.workspaceWindows = Dictionary(
      uniqueKeysWithValues: normalizedWorkspaceNames.map { ($0, []) }
    )
    self.pendingPersistedWorkspaceWindowKeys = persistedSnapshot?.workspaceWindows ?? [:]
    self.pendingPersistedSavedFrames = persistedSnapshot?.savedFrames ?? [:]
    self.lastPersistedWorkspaceSnapshot = nil
    self.lastFocusedManagedWindowKeyByDisplay = [:]
    self.lastFocusedManagedWindowWorkspaceNameByDisplay = [:]

    var initialActiveWorkspaceNamesByDisplay: [WorkspaceDisplayRole: String] = [:]
    if let fallbackWorkspace = normalizedWorkspaceNames.first {
      let restoredWorkspace = persistedSnapshot?.activeWorkspaceNamesByDisplay[
        WorkspaceDisplayRole.primary.rawValue
      ]
      initialActiveWorkspaceNamesByDisplay[.primary] = restoredWorkspace.flatMap { workspaceName in
        normalizedWorkspaceNames.contains(workspaceName) ? workspaceName : nil
      } ?? fallbackWorkspace
    }
    self.activeWorkspaceNamesByDisplay = initialActiveWorkspaceNamesByDisplay
    self.previousWorkspaceNamesByDisplay = [:]
    self.activeWorkspaceName = initialActiveWorkspaceNamesByDisplay[.primary]
      ?? normalizedWorkspaceNames.first
      ?? WorkspaceConfig.defaultNames[0]
    self.previousWorkspaceName = nil

    restorePersistedWorkspaceMappingIfNeeded()
    refreshCompatibilityState()
  }

  var state: VirtualWorkspaceState {
    VirtualWorkspaceState(
      enabled: enabled,
      workspaceNames: workspaceNames,
      activeWorkspaceName: activeWorkspaceName,
      previousWorkspaceName: previousWorkspaceName,
      displayStates: displayStates
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

    let normalizedWorkspaceNames = Self.normalizeWorkspaceNames(
      config.primaryNames,
      fallback: WorkspaceConfig.defaultNames
    )

    workspaceNames = normalizedWorkspaceNames
    enabled = config.enabled

    let fallbackWorkspace = normalizedWorkspaceNames.first ?? WorkspaceConfig.defaultNames[0]

    var remappedWorkspaceWindows: [String: [ManagedWindowRef]] =
      Dictionary(uniqueKeysWithValues: normalizedWorkspaceNames.map { ($0, []) })

    for (workspaceName, windows) in workspaceWindows {
      let targetWorkspaceName = if normalizedWorkspaceNames.contains(workspaceName) {
        workspaceName
      } else {
        fallbackWorkspace
      }
      for window in windows {
        Self.appendUnique(window, to: &remappedWorkspaceWindows[targetWorkspaceName, default: []])
      }
    }
    workspaceWindows = remappedWorkspaceWindows

    let currentActiveWorkspaceName = activeWorkspaceNamesByDisplay[.primary]
    activeWorkspaceNamesByDisplay = [
      .primary: currentActiveWorkspaceName.flatMap { workspaceName in
        normalizedWorkspaceNames.contains(workspaceName) ? workspaceName : nil
      } ?? fallbackWorkspace
    ]

    previousWorkspaceNamesByDisplay = previousWorkspaceNamesByDisplay.reduce(
      into: [WorkspaceDisplayRole: String]()
    ) { partialResult, entry in
      let workspaceName = entry.value
      guard normalizedWorkspaceNames.contains(workspaceName) else { return }
      partialResult[.primary] = workspaceName
    }

    lastFocusedManagedWindowKeyByDisplay = lastFocusedManagedWindowKeyByDisplay.filter {
      $0.key == .primary
    }
    lastFocusedManagedWindowWorkspaceNameByDisplay = lastFocusedManagedWindowWorkspaceNameByDisplay.reduce(
      into: [WorkspaceDisplayRole: String]()
    ) { partialResult, entry in
      let workspaceName = entry.value
      guard normalizedWorkspaceNames.contains(workspaceName) else { return }
      partialResult[.primary] = workspaceName
    }

    refreshCompatibilityState()

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    if wasEnabled && !enabled {
      restoreAllWindows()
    } else if enabled && driver.isAccessibilityGranted() {
      _ = reconcileVisibility()
    }

    notifyStateDidChange()
  }

  func synchronizeActiveWorkspaceToFocusedWindowIfNeeded() {
    guard enabled else { return }
    guard !workspaceNames.isEmpty else { return }
    guard driver.isAccessibilityGranted() else { return }

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    guard let focusedWindow = driver.resolveFocusedWindow(
      preferredWindow: nil,
      allowFallbackWindow: false
    ) else {
      restoreFocusForClosedManagedWindowIfNeeded()
      return
    }
    if isSpecialWindow(focusedWindow) {
      return
    }

    guard let displayRole = displayRole(for: focusedWindow) else {
      return
    }
    guard let activeWorkspaceName = activeWorkspaceName(for: displayRole) else { return }

    let activeWorkspaceHasLiveWindows = hasLiveManagedWindow(in: activeWorkspaceName)
    let lastFocusedWindowClosedInActiveWorkspace = {
      guard let lastFocusedWorkspaceName = lastFocusedManagedWindowWorkspaceNameByDisplay[displayRole],
        let lastFocusedKey = lastFocusedManagedWindowKeyByDisplay[displayRole]
      else {
        return false
      }

      return lastFocusedWorkspaceName == activeWorkspaceName
        && workspaceName(for: lastFocusedKey) == nil
    }()

    guard let focusedWindowWorkspace = workspaceName(for: focusedWindow.key) else {
      return
    }
    if focusedWindowWorkspace == activeWorkspaceName {
      recordFocusedWindow(focusedWindow, in: focusedWindowWorkspace, on: displayRole)
      return
    }

    if !activeWorkspaceHasLiveWindows {
      clearLastFocusedManagedWindow(on: displayRole)
      return
    }

    if lastFocusedWindowClosedInActiveWorkspace {
      restoreFocusAfterClosedWindowIfPossible(on: displayRole)
      return
    }

    recordFocusedWindow(focusedWindow, in: focusedWindowWorkspace, on: displayRole)

    _ = focusWorkspace(
      focusedWindowWorkspace,
      preserveFocusedWindow: true
    )
  }

  func synchronizeActiveWorkspaceToApplicationIfNeeded(processIdentifier: pid_t?) {
    guard enabled else { return }
    guard !workspaceNames.isEmpty else { return }
    guard driver.isAccessibilityGranted() else { return }
    guard let processIdentifier else { return }
    guard processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    guard let targetWorkspaceName = workspaceName(containingWindowForProcessIdentifier: processIdentifier),
      let displayRole = workspaceRole(for: targetWorkspaceName),
      let activeWorkspaceName = activeWorkspaceName(for: displayRole)
    else {
      return
    }
    guard targetWorkspaceName != activeWorkspaceName else { return }

    _ = focusWorkspace(targetWorkspaceName)
  }

  func handleObservedWindowDestroyed() {
    guard enabled else { return }
    guard !workspaceNames.isEmpty else { return }
    guard driver.isAccessibilityGranted() else { return }

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    restoreFocusForClosedManagedWindowIfNeeded()
  }

  func focusWorkspace(
    _ workspaceName: String,
    preserveFocusedWindow: Bool = false
  ) -> Result<Void, WorkspaceError> {
    guard enabled else { return .failure(.workspaceDisabled) }
    guard workspaceNames.contains(workspaceName) else { return .failure(.invalidWorkspace) }
    guard driver.isAccessibilityGranted() else { return .failure(.permissionDenied) }
    guard let displayRole = workspaceRole(for: workspaceName),
      let currentWorkspace = activeWorkspaceName(for: displayRole)
    else {
      return .failure(.invalidWorkspace)
    }

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    guard workspaceName != currentWorkspace else {
      persistWorkspaceSnapshotIfNeeded()
      return .success(())
    }

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

    previousWorkspaceNamesByDisplay[displayRole] = currentWorkspace
    activeWorkspaceNamesByDisplay[displayRole] = workspaceName
    refreshCompatibilityState()
    if !preserveFocusedWindow {
      focusPreferredWindow(in: workspaceName)
    }
    notifyStateDidChange()

    return hasApplyFailure ? .failure(.applyFailed) : .success(())
  }

  func focusPreviousWorkspace() -> Result<Void, WorkspaceError> {
    let targetRole = targetDisplayRoleForWorkspaceCommands()
    guard let previousWorkspaceName = previousWorkspaceNamesByDisplay[targetRole],
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

    synchronizeManageableWindowsToActiveWorkspace()
    pruneDeadWindows()

    guard let focusedWindow = driver.resolveFocusedWindow(
      preferredWindow: preferredWindowElement,
      allowFallbackWindow: true
    ) else {
      return .failure(.noFocusedWindow)
    }
    if isSpecialWindow(focusedWindow) {
      removeWindowFromAllWorkspaces(focusedWindow)
      savedFrames.removeValue(forKey: focusedWindow.key)
      notifyStateDidChange()
      return .success(())
    }
    guard let displayRole = displayRole(for: focusedWindow) else {
      removeWindowFromAllWorkspaces(focusedWindow)
      savedFrames.removeValue(forKey: focusedWindow.key)
      notifyStateDidChange()
      return .success(())
    }
    guard workspaceRole(for: workspaceName) == displayRole else {
      return .failure(.invalidWorkspace)
    }

    removeWindowFromAllWorkspaces(focusedWindow)
    Self.appendUnique(focusedWindow, to: &workspaceWindows[workspaceName, default: []])

    let didApply = if workspaceName == activeWorkspaceName(for: displayRole) {
      unhide(focusedWindow)
    } else {
      hide(focusedWindow)
    }

    notifyStateDidChange()
    return didApply ? .success(()) : .failure(.applyFailed)
  }

  func restoreAllWindows() {
    pruneDeadWindows()

    let windows = allManagedWindows

    for window in windows {
      guard let savedFrame = savedFrames[window.key] else { continue }
      let displayRole = displayRole(for: window)

      if driver.setFrame(savedFrame, for: window) {
        savedFrames.removeValue(forKey: window.key)
        continue
      }

      guard let displayRole,
        let visibleFrame = visibleFrame(for: displayRole),
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

    persistWorkspaceSnapshotIfNeeded()
  }

  func managedWindowKeys(in workspaceName: String) -> [WindowKey] {
    workspaceWindows[workspaceName, default: []].map(\.key)
  }

  func workspaceName(for windowKey: WindowKey) -> String? {
    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      if windows.contains(where: { $0.key == windowKey }) {
        return workspaceName
      }
    }

    return nil
  }

  private func workspaceName(containingWindowForProcessIdentifier processIdentifier: pid_t) -> String? {
    let currentActiveWorkspaceName = activeWorkspaceName
    if workspaceWindows[currentActiveWorkspaceName, default: []].contains(where: {
        $0.processIdentifier == processIdentifier
      })
    {
      return currentActiveWorkspaceName
    }

    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      if windows.contains(where: { $0.processIdentifier == processIdentifier }) {
        return workspaceName
      }
    }

    return nil
  }

  private var workspaceWindowKeysMapping: [String: [WindowKey]] {
    Dictionary(
      uniqueKeysWithValues: workspaceNames.map { workspaceName in
        (workspaceName, workspaceWindows[workspaceName, default: []].map(\.key))
      }
    )
  }

  private var persistedSavedFrames: [WindowKey: PersistedWindowFrame] {
    savedFrames.reduce(into: [WindowKey: PersistedWindowFrame]()) { partialResult, entry in
      partialResult[entry.key] = PersistedWindowFrame(rect: entry.value)
    }
  }

  private var workspaceMappingSnapshot: WorkspaceMappingSnapshot {
    WorkspaceMappingSnapshot(
      activeWorkspaceNamesByDisplay: persistedActiveWorkspaceNamesByDisplay,
      workspaceWindows: workspaceWindowKeysMapping,
      savedFrames: persistedSavedFrames
    )
  }

  private var allManagedWindows: [ManagedWindowRef] {
    var uniqueKeys: Set<WindowKey> = []
    var orderedWindows: [ManagedWindowRef] = []
    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      for window in windows {
        guard uniqueKeys.insert(window.key).inserted else { continue }
        orderedWindows.append(window)
      }
    }
    return orderedWindows
  }

  private func reconcileVisibility() -> Bool {
    var success = true
    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      let isActiveWorkspace = if let displayRole = workspaceRole(for: workspaceName) {
        workspaceName == activeWorkspaceName(for: displayRole)
      } else {
        false
      }

      if isActiveWorkspace {
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
    guard let displayRole = displayRole(for: window),
      let visibleFrame = visibleFrame(for: displayRole)
    else {
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
    let liveWindows = manageableWindowsOnManagedDisplays
    let liveWindowsByKey = Dictionary(uniqueKeysWithValues: liveWindows.map { ($0.key, $0) })

    for workspaceName in workspaceNames {
      let windows = workspaceWindows[workspaceName, default: []]
      var uniqueKeys: Set<WindowKey> = []
      var prunedWindows: [ManagedWindowRef] = []
      for window in windows {
        guard let liveWindow = liveWindowsByKey[window.key] else { continue }
        guard uniqueKeys.insert(window.key).inserted else { continue }
        prunedWindows.append(liveWindow)
      }
      workspaceWindows[workspaceName] = prunedWindows
    }

    let aliveKeys = Set(liveWindowsByKey.keys)
    savedFrames = savedFrames.filter { aliveKeys.contains($0.key) }
  }

  private func removeWindowFromAllWorkspaces(_ target: ManagedWindowRef) {
    for workspaceName in workspaceNames {
      workspaceWindows[workspaceName, default: []].removeAll { $0.key == target.key }
    }
  }

  private func restorePersistedWorkspaceMappingIfNeeded() {
    guard !pendingPersistedWorkspaceWindowKeys.isEmpty || !pendingPersistedSavedFrames.isEmpty else {
      return
    }
    guard enabled else { return }
    guard !workspaceNames.isEmpty else { return }
    guard driver.isAccessibilityGranted() else { return }

    var restoredWorkspaceWindows: [String: [ManagedWindowRef]] =
      Dictionary(uniqueKeysWithValues: workspaceNames.map { ($0, []) })
    let liveWindows = manageableWindowsOnManagedDisplays
    let liveWindowsByKey = Dictionary(uniqueKeysWithValues: liveWindows.map { ($0.key, $0) })
    var assignedWindowKeys: Set<WindowKey> = []
    var liveWindowKeysByPersistedKey: [WindowKey: WindowKey] = [:]

    for workspaceName in workspaceNames {
      for persistedKey in pendingPersistedWorkspaceWindowKeys[workspaceName, default: []] {
        guard
          let window = restoredWindow(
            forPersistedKey: persistedKey,
            liveWindowsByKey: liveWindowsByKey,
            liveWindows: liveWindows,
            assignedWindowKeys: assignedWindowKeys
          )
        else {
          continue
        }
        guard workspaceRole(for: workspaceName) == displayRole(for: window) else { continue }
        guard assignedWindowKeys.insert(window.key).inserted else { continue }
        liveWindowKeysByPersistedKey[persistedKey] = window.key
        Self.appendUnique(window, to: &restoredWorkspaceWindows[workspaceName, default: []])
      }
    }

    for window in liveWindows where !assignedWindowKeys.contains(window.key) {
      guard let displayRole = displayRole(for: window),
        let activeWorkspaceName = activeWorkspaceName(for: displayRole)
      else {
        continue
      }
      Self.appendUnique(window, to: &restoredWorkspaceWindows[activeWorkspaceName, default: []])
    }

    workspaceWindows = restoredWorkspaceWindows
    savedFrames = pendingPersistedSavedFrames.reduce(into: [WindowKey: CGRect]()) { partialResult, entry in
      let windowKey = liveWindowKeysByPersistedKey[entry.key] ?? entry.key
      guard liveWindowsByKey[windowKey] != nil else { return }
      guard let workspaceName = workspaceName(for: windowKey),
        let displayRole = workspaceRole(for: workspaceName),
        let activeWorkspaceName = activeWorkspaceName(for: displayRole)
      else {
        return
      }
      guard workspaceName != activeWorkspaceName else { return }

      partialResult[windowKey] = entry.value.rect
    }
    pendingPersistedWorkspaceWindowKeys = [:]
    pendingPersistedSavedFrames = [:]

    _ = reconcileVisibility()
  }

  private func restoredWindow(
    forPersistedKey persistedKey: WindowKey,
    liveWindowsByKey: [WindowKey: ManagedWindowRef],
    liveWindows: [ManagedWindowRef],
    assignedWindowKeys: Set<WindowKey>
  ) -> ManagedWindowRef? {
    if let window = liveWindowsByKey[persistedKey],
      !assignedWindowKeys.contains(window.key)
    {
      return window
    }

    guard let persistedProcessIdentifier = Self.processIdentifier(fromFallbackWindowKey: persistedKey) else {
      return nil
    }

    let candidates = liveWindows.filter { window in
      !assignedWindowKeys.contains(window.key)
        && window.processIdentifier == persistedProcessIdentifier
        && Self.processIdentifier(fromFallbackWindowKey: window.key) != nil
    }

    return candidates.count == 1 ? candidates[0] : nil
  }

  private func persistWorkspaceSnapshotIfNeeded() {
    let snapshot = workspaceMappingSnapshot
    guard snapshot != lastPersistedWorkspaceSnapshot else { return }

    workspaceMappingStore.save(snapshot)
    lastPersistedWorkspaceSnapshot = snapshot
  }

  private func synchronizeManageableWindowsToActiveWorkspace() {
    restorePersistedWorkspaceMappingIfNeeded()

    guard enabled else { return }
    guard !workspaceNames.isEmpty else { return }
    guard driver.isAccessibilityGranted() else { return }

    let knownKeys = Set(allManagedWindows.map(\.key))
    for window in manageableWindowsOnManagedDisplays where !knownKeys.contains(window.key) {
      guard let displayRole = displayRole(for: window),
        let activeWorkspaceName = activeWorkspaceName(for: displayRole)
      else {
        continue
      }

      Self.appendUnique(window, to: &workspaceWindows[activeWorkspaceName, default: []])
    }
  }

  private func focusPreferredWindow(in workspaceName: String) {
    focusTopmostWindow(in: workspaceName)
  }

  @discardableResult
  private func focusTopmostWindow(in workspaceName: String) -> ManagedWindowRef? {
    let windows = workspaceWindows[workspaceName, default: []]
    for window in windows.reversed() where !isSpecialWindow(window) && driver.isWindowAlive(window) {
      guard let displayRole = workspaceRole(for: workspaceName) else { continue }
      if driver.focus(window) {
        recordFocusedWindow(window, in: workspaceName, on: displayRole)
        return window
      }
    }

    return nil
  }

  private func restoreFocusAfterClosedWindowIfPossible(on displayRole: WorkspaceDisplayRole) {
    guard let activeWorkspaceName = activeWorkspaceName(for: displayRole) else {
      clearLastFocusedManagedWindow(on: displayRole)
      return
    }
    guard hasLiveManagedWindow(in: activeWorkspaceName) else {
      clearLastFocusedManagedWindow(on: displayRole)
      return
    }

    guard let topmostWindow = topmostManagedWindow(in: activeWorkspaceName) else {
      clearLastFocusedManagedWindow(on: displayRole)
      return
    }

    if focusTopmostWindow(in: activeWorkspaceName) == nil {
      lastFocusedManagedWindowKeyByDisplay[displayRole] = topmostWindow.key
      lastFocusedManagedWindowWorkspaceNameByDisplay[displayRole] = activeWorkspaceName
    }
  }

  private func hasLiveManagedWindow(in workspaceName: String) -> Bool {
    workspaceWindows[workspaceName, default: []].contains {
      !isSpecialWindow($0) && driver.isWindowAlive($0)
    }
  }

  private func topmostManagedWindow(in workspaceName: String) -> ManagedWindowRef? {
    workspaceWindows[workspaceName, default: []]
      .reversed()
      .first(where: { !isSpecialWindow($0) && driver.isWindowAlive($0) })
  }

  private func recordFocusedWindow(
    _ window: ManagedWindowRef,
    in workspaceName: String,
    on displayRole: WorkspaceDisplayRole
  ) {
    promoteWindowToTopmost(window, in: workspaceName)
    lastFocusedManagedWindowKeyByDisplay[displayRole] = window.key
    lastFocusedManagedWindowWorkspaceNameByDisplay[displayRole] = workspaceName
  }

  private func promoteWindowToTopmost(
    _ window: ManagedWindowRef,
    in workspaceName: String
  ) {
    var windows = workspaceWindows[workspaceName, default: []]
    windows.removeAll { $0.key == window.key }
    windows.append(window)
    workspaceWindows[workspaceName] = windows
  }

  private func clearLastFocusedManagedWindow(on displayRole: WorkspaceDisplayRole) {
    lastFocusedManagedWindowKeyByDisplay.removeValue(forKey: displayRole)
    lastFocusedManagedWindowWorkspaceNameByDisplay.removeValue(forKey: displayRole)
  }

  private func isSpecialWindow(_ window: ManagedWindowRef) -> Bool {
    guard let element = window.element else { return false }

    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else {
      return false
    }

    if pid == ProcessInfo.processInfo.processIdentifier {
      return true
    }

    guard let currentBundleIdentifier = Bundle.main.bundleIdentifier else {
      return false
    }
    guard
      let bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    else {
      return false
    }

    return bundleIdentifier == currentBundleIdentifier
  }

  private func notifyStateDidChange() {
    refreshCompatibilityState()
    persistWorkspaceSnapshotIfNeeded()
    onStateDidChange?(state)
  }

  private static func appendUnique(_ window: ManagedWindowRef, to windows: inout [ManagedWindowRef]) {
    guard !windows.contains(where: { $0.key == window.key }) else { return }
    windows.append(window)
  }

  private func activeWorkspaceName(for displayRole: WorkspaceDisplayRole) -> String? {
    activeWorkspaceNamesByDisplay[displayRole]
  }

  private func visibleFrame(for displayRole: WorkspaceDisplayRole) -> CGRect? {
    guard displayRole == .primary else { return nil }
    return driver.visibleFrame()
  }

  private func screenFrame(for displayRole: WorkspaceDisplayRole) -> CGRect? {
    guard displayRole == .primary else { return nil }
    return driver.screenFrame()
  }

  private var managedDisplayRoles: [WorkspaceDisplayRole] {
    workspaceNames.isEmpty ? [] : [.primary]
  }

  private var displayStates: [WorkspaceDisplayRole: WorkspaceDisplayState] {
    guard let activeWorkspaceName = activeWorkspaceName(for: .primary) else {
      return [:]
    }

    return [
      .primary: WorkspaceDisplayState(
        workspaceNames: workspaceNames,
        activeWorkspaceName: activeWorkspaceName,
        previousWorkspaceName: previousWorkspaceNamesByDisplay[.primary],
        appNamesByWorkspace: appNamesByWorkspace
      )
    ]
  }

  private var manageableWindowsOnManagedDisplays: [ManagedWindowRef] {
    driver.allManageableWindows().filter { window in
      !isSpecialWindow(window) && displayRole(for: window) != nil
    }
  }

  private var appNamesByWorkspace: [String: [String]] {
    Dictionary(
      uniqueKeysWithValues: workspaceNames.map { workspaceName in
        var seen: Set<String> = []
        var appNames: [String] = []
        for window in workspaceWindows[workspaceName, default: []] {
          let appName = window.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          guard !appName.isEmpty else { continue }
          guard seen.insert(appName).inserted else { continue }
          appNames.append(appName)
        }
        return (workspaceName, appNames)
      }
    )
  }

  private var persistedActiveWorkspaceNamesByDisplay: [String: String] {
    activeWorkspaceNamesByDisplay.reduce(into: [String: String]()) { partialResult, entry in
      partialResult[entry.key.rawValue] = entry.value
    }
  }

  private func workspaceRole(for workspaceName: String) -> WorkspaceDisplayRole? {
    workspaceNames.contains(workspaceName) ? .primary : nil
  }

  private func displayRole(for window: ManagedWindowRef) -> WorkspaceDisplayRole? {
    let frame = savedFrames[window.key] ?? driver.frame(for: window)
    guard let frame, !frame.isNull else {
      return nil
    }

    return displayRole(for: frame)
  }

  private func displayRole(for frame: CGRect) -> WorkspaceDisplayRole? {
    var bestRole: WorkspaceDisplayRole?
    var bestIntersectionArea: CGFloat = 0

    for displayRole in managedDisplayRoles {
      guard let screenFrame = screenFrame(for: displayRole) else { continue }

      let intersectionArea = frame.intersection(screenFrame).area
      if intersectionArea > bestIntersectionArea {
        bestIntersectionArea = intersectionArea
        bestRole = displayRole
      }
    }

    if let bestRole {
      return bestRole
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    for displayRole in managedDisplayRoles {
      guard let screenFrame = screenFrame(for: displayRole) else { continue }
      if screenFrame.contains(center) {
        return displayRole
      }
    }

    return nil
  }

  private func targetDisplayRoleForWorkspaceCommands() -> WorkspaceDisplayRole {
    .primary
  }

  private func restoreFocusForClosedManagedWindowIfNeeded() {
    for displayRole in managedDisplayRoles {
      guard let activeWorkspaceName = activeWorkspaceName(for: displayRole),
        let lastFocusedWindowKey = lastFocusedManagedWindowKeyByDisplay[displayRole],
        lastFocusedManagedWindowWorkspaceNameByDisplay[displayRole] == activeWorkspaceName,
        workspaceName(for: lastFocusedWindowKey) == nil
      else {
        continue
      }

      restoreFocusAfterClosedWindowIfPossible(on: displayRole)
    }
  }

  private func refreshCompatibilityState() {
    activeWorkspaceName = activeWorkspaceNamesByDisplay[.primary]
      ?? workspaceNames.first
      ?? WorkspaceConfig.defaultNames[0]
    previousWorkspaceName = previousWorkspaceNamesByDisplay[.primary]
  }

  private static func normalizeWorkspaceNames(_ names: [String], fallback: [String]) -> [String] {
    var normalized: [String] = []
    var seen: Set<String> = []

    for rawName in names {
      let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { continue }
      guard seen.insert(trimmedName).inserted else { continue }
      normalized.append(trimmedName)
    }

    return normalized.isEmpty ? fallback : normalized
  }

  private static func processIdentifier(fromFallbackWindowKey key: WindowKey) -> pid_t? {
    guard key.hasPrefix("axel:") else { return nil }

    let parts = key.split(separator: ":")
    guard parts.count == 3, let processIdentifier = Int32(String(parts[1])) else {
      return nil
    }

    return pid_t(processIdentifier)
  }

  private static func hiddenFrame(for frame: CGRect, in visibleFrame: CGRect) -> CGRect {
    let width = max(1, frame.width)
    let height = max(1, frame.height)
    let hideOnRightSide = frame.midX >= visibleFrame.midX

    let hiddenX = if hideOnRightSide {
      visibleFrame.maxX - 1
    } else {
      visibleFrame.minX - width + 1
    }

    return CGRect(
      x: hiddenX,
      y: visibleFrame.minY - 1,
      width: width,
      height: height
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

private extension CGRect {
  var area: CGFloat {
    guard !isNull, !isEmpty else { return 0 }
    return width * height
  }
}
