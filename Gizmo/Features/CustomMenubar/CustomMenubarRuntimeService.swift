import AppKit
import OSLog

@MainActor
final class CustomMenubarRuntimeService: NSObject, CustomMenubarPresenting {
  private let logger = Logger(subsystem: "com.yihyunjoon.Gizmo", category: "CustomMenubar")

  private var spaceManager: SkyLightSpaceManager?
  private var windows: [WorkspaceDisplayRole: CustomMenubarWindowController] = [:]
  private var skylightAttachedDisplayRoles: Set<WorkspaceDisplayRole> = []

  private var screenObserver: NSObjectProtocol?
  private var activeSpaceObserver: NSObjectProtocol?

  private var modelsByDisplayRole: [WorkspaceDisplayRole: CustomMenubarModel] = [:]
  private var onWorkspaceSelection: ((String) -> Void)?
  private var workspaceState = VirtualWorkspaceState(
    enabled: WorkspaceConfig.default.enabled,
    mode: .primaryOnly,
    workspaceNames: WorkspaceConfig.default.primaryNames,
    activeWorkspaceName: WorkspaceConfig.default.primaryNames.first ?? WorkspaceConfig.defaultNames[0],
    previousWorkspaceName: nil,
    displayStates: [
      .primary: WorkspaceDisplayState(
        workspaceNames: WorkspaceConfig.default.primaryNames,
        activeWorkspaceName: WorkspaceConfig.default.primaryNames.first ?? WorkspaceConfig.defaultNames[0],
        previousWorkspaceName: nil
      )
    ]
  )

  private(set) var isRunning = false
  private(set) var config: CustomMenubarConfig = .default

  override init() {
    super.init()
  }

  func start() {
    guard !isRunning else { return }

    isRunning = true
    reconcileModels()
    observeScreenChangesIfNeeded()
    observeSpaceChangesIfNeeded()
    reconcileWindows()
  }

  func stop() {
    guard isRunning else { return }

    isRunning = false
    removeObservers()
    tearDownWindows()
    tearDownModels()
  }

  func apply(config: CustomMenubarConfig) {
    self.config = config
    for model in modelsByDisplayRole.values {
      model.apply(config: config)
    }

    guard isRunning else { return }
    reconcileModels()
    reconcileWindows()
  }

  func reconfigureForDisplayChanges() {
    guard isRunning else { return }
    reconcileWindows()
  }

  func setWorkspaceSelectionHandler(_ handler: @escaping (String) -> Void) {
    onWorkspaceSelection = handler

    guard isRunning else { return }
    reconcileWindows()
  }

  func updateWorkspaceState(_ state: VirtualWorkspaceState) {
    workspaceState = state
    reconcileModels()

    guard isRunning else { return }
    reconcileWindows()
  }

  private func observeScreenChangesIfNeeded() {
    guard screenObserver == nil else { return }

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reconfigureForDisplayChanges()
    }
  }

  private func observeSpaceChangesIfNeeded() {
    guard activeSpaceObserver == nil else { return }

    activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.reconfigureForDisplayChanges()
    }
  }

  private func removeObservers() {
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
      self.screenObserver = nil
    }

    if let activeSpaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
      self.activeSpaceObserver = nil
    }
  }

  private func reconcileWindows() {
    guard isRunning else { return }

    guard config.enabled else {
      tearDownWindows()
      return
    }

    let hasSkyLight = ensureSpaceManager()
    if !hasSkyLight {
      skylightAttachedDisplayRoles.removeAll()
    }

    let targets = resolvedDisplayTargets()
    guard !targets.isEmpty else {
      tearDownWindows()
      return
    }

    let targetRoles = Set(targets.map(\.role))

    for (role, controller) in windows where !targetRoles.contains(role) {
      controller.close()
      windows.removeValue(forKey: role)
      skylightAttachedDisplayRoles.remove(role)
    }

    for target in targets {
      let role = target.role
      let screen = target.screen

      guard let model = model(for: role) else {
        continue
      }

      if let controller = windows[role] {
        controller.update(
          screen: screen,
          model: model,
          config: config,
          onWorkspaceTap: workspaceTapHandler()
        )
        if hasSkyLight, !skylightAttachedDisplayRoles.contains(role), let window = controller.window {
          attachWindowToSkyLight(window, role: role, attemptsRemaining: 8)
        }
        if shouldHideInFullscreen(for: screen, role: role) {
          controller.hide()
        } else {
          controller.show()
        }
        continue
      }

      let controller = CustomMenubarWindowController(
        screen: screen,
        model: model,
        config: config,
        onWorkspaceTap: workspaceTapHandler()
      )

      windows[role] = controller

      guard let window = controller.window else {
        logger.error("Failed to resolve NSWindow for display role=\(role.rawValue, privacy: .public)")
        controller.close()
        windows.removeValue(forKey: role)
        continue
      }

      if hasSkyLight {
        attachWindowToSkyLight(window, role: role, attemptsRemaining: 8)
      }

      if shouldHideInFullscreen(for: screen, role: role) {
        controller.hide()
      } else {
        controller.show()
      }
    }
  }

  private func ensureSpaceManager() -> Bool {
    if spaceManager != nil { return true }

    do {
      spaceManager = try SkyLightSpaceManager()
      return true
    } catch {
      logger.error("SkyLight initialization failed: \(error.localizedDescription, privacy: .public)")
      spaceManager = nil
      return false
    }
  }

  private func tearDownWindows() {
    for windowController in windows.values {
      windowController.close()
    }

    windows.removeAll()
    skylightAttachedDisplayRoles.removeAll()
    spaceManager = nil
  }

  private func tearDownModels() {
    for model in modelsByDisplayRole.values {
      model.stop()
    }

    modelsByDisplayRole.removeAll()
  }

  private func attachWindowToSkyLight(
    _ window: NSWindow,
    role: WorkspaceDisplayRole,
    attemptsRemaining: Int
  ) {
    guard let spaceManager else { return }

    do {
      try spaceManager.attachWindow(window)
      skylightAttachedDisplayRoles.insert(role)
    } catch {
      if attemptsRemaining > 0 {
        let retryDelay = DispatchTimeInterval.milliseconds(60)
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self, weak window] in
          guard let self, let window else { return }
          self.attachWindowToSkyLight(
            window,
            role: role,
            attemptsRemaining: attemptsRemaining - 1
          )
        }
        return
      }

      logger.error(
        "SkyLight attach failed for display role=\(role.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      skylightAttachedDisplayRoles.remove(role)
      logger.error(
        "Keeping overlay window visible without SkyLight space binding for display role=\(role.rawValue, privacy: .public)"
      )
      windows[role]?.show()
    }
  }

  private func shouldHideInFullscreen(for screen: NSScreen, role: WorkspaceDisplayRole) -> Bool {
    guard skylightAttachedDisplayRoles.contains(role) else {
      return false
    }

    guard let spaceManager else {
      return false
    }

    return spaceManager.isFullscreen(screen: screen)
  }

  private func reconcileModels() {
    let targetRoles = Set(targetDisplayRoles())

    for (role, model) in modelsByDisplayRole where !targetRoles.contains(role) {
      model.stop()
      modelsByDisplayRole.removeValue(forKey: role)
    }

    for role in targetRoles {
      let model = modelsByDisplayRole[role] ?? {
        let nextModel = CustomMenubarModel()
        modelsByDisplayRole[role] = nextModel
        return nextModel
      }()

      model.apply(config: config)

      if let displayState = workspaceState.displayStates[role] {
        model.updateWorkspaceState(
          names: displayState.workspaceNames,
          focusedWorkspaceName: displayState.activeWorkspaceName
        )
      }

      if isRunning {
        model.start()
      }
    }
  }

  private func model(for role: WorkspaceDisplayRole) -> CustomMenubarModel? {
    if modelsByDisplayRole[role] == nil {
      reconcileModels()
    }

    return modelsByDisplayRole[role]
  }

  private func targetDisplayRoles() -> [WorkspaceDisplayRole] {
    switch workspaceState.mode {
    case .primaryOnly, .unified:
      return workspaceState.displayStates[.primary] == nil ? [] : [.primary]
    case .perDisplay:
      return WorkspaceDisplayRole.allCases.filter { workspaceState.displayStates[$0] != nil }
    }
  }

  private func resolvedDisplayTargets() -> [(role: WorkspaceDisplayRole, screen: NSScreen)] {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return [] }

    var targets: [(role: WorkspaceDisplayRole, screen: NSScreen)] = []

    for role in targetDisplayRoles() {
      guard let screen = screen(for: role) else { continue }
      targets.append((role: role, screen: screen))
    }

    return targets
  }

  private func screen(for role: WorkspaceDisplayRole) -> NSScreen? {
    switch role {
    case .primary:
      return NSScreen.screens.first
    case .secondary:
      let screens = NSScreen.screens
      guard screens.count >= 2 else { return nil }
      return screens[1]
    }
  }

  private func workspaceTapHandler() -> (String) -> Void {
    { [weak self] workspaceName in
      self?.onWorkspaceSelection?(workspaceName)
    }
  }
}
