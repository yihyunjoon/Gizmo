import AppKit
import OSLog

@MainActor
final class CustomMenubarRuntimeService: NSObject, CustomMenubarPresenting {
  private let logger = Logger(subsystem: "com.yihyunjoon.Gizmo", category: "CustomMenubar")

  private var spaceManager: SkyLightSpaceManager?
  private var windows: [String: CustomMenubarWindowController] = [:]
  private var skylightAttachedScreenIDs: Set<String> = []

  private var screenObserver: NSObjectProtocol?
  private var activeSpaceObserver: NSObjectProtocol?

  private let model = CustomMenubarModel()
  private var onWorkspaceSelection: ((String) -> Void)?

  private(set) var isRunning = false
  private(set) var config: CustomMenubarConfig = .default

  override init() {
    super.init()
  }

  func start() {
    guard !isRunning else { return }

    isRunning = true
    model.start()
    observeScreenChangesIfNeeded()
    observeSpaceChangesIfNeeded()
    reconcileWindows()
  }

  func stop() {
    guard isRunning else { return }

    isRunning = false
    removeObservers()
    tearDownWindows()
    model.stop()
  }

  func apply(config: CustomMenubarConfig) {
    self.config = config
    model.apply(config: config)

    guard isRunning else { return }
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

  func updateWorkspaceState(
    names: [String],
    focusedWorkspaceName: String
  ) {
    model.updateWorkspaceState(
      names: names,
      focusedWorkspaceName: focusedWorkspaceName
    )
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
      skylightAttachedScreenIDs.removeAll()
    }

    let targetScreens = resolvedScreens(scope: config.displayScope)
    guard !targetScreens.isEmpty else {
      tearDownWindows()
      return
    }

    let targetIDs = Set(targetScreens.map(screenIdentifier(_:)))

    for (id, controller) in windows where !targetIDs.contains(id) {
      controller.close()
      windows.removeValue(forKey: id)
      skylightAttachedScreenIDs.remove(id)
    }

    for screen in targetScreens {
      let id = screenIdentifier(screen)

      if let controller = windows[id] {
        controller.update(
          screen: screen,
          model: model,
          config: config,
          onWorkspaceTap: workspaceTapHandler()
        )
        if hasSkyLight, !skylightAttachedScreenIDs.contains(id), let window = controller.window {
          attachWindowToSkyLight(window, screenID: id, attemptsRemaining: 8)
        }
        if shouldHideInFullscreen(for: screen, screenID: id) {
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

      windows[id] = controller

      guard let window = controller.window else {
        logger.error("Failed to resolve NSWindow for screen id=\(id, privacy: .public)")
        controller.close()
        windows.removeValue(forKey: id)
        continue
      }

      if hasSkyLight {
        attachWindowToSkyLight(window, screenID: id, attemptsRemaining: 8)
      }

      if shouldHideInFullscreen(for: screen, screenID: id) {
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
    skylightAttachedScreenIDs.removeAll()
    spaceManager = nil
  }

  private func attachWindowToSkyLight(
    _ window: NSWindow,
    screenID: String,
    attemptsRemaining: Int
  ) {
    guard let spaceManager else { return }

    do {
      try spaceManager.attachWindow(window)
      skylightAttachedScreenIDs.insert(screenID)
    } catch {
      if attemptsRemaining > 0 {
        let retryDelay = DispatchTimeInterval.milliseconds(60)
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self, weak window] in
          guard let self, let window else { return }
          self.attachWindowToSkyLight(
            window,
            screenID: screenID,
            attemptsRemaining: attemptsRemaining - 1
          )
        }
        return
      }

      logger.error(
        "SkyLight attach failed for screen id=\(screenID, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      skylightAttachedScreenIDs.remove(screenID)
      logger.error(
        "Keeping overlay window visible without SkyLight space binding for screen id=\(screenID, privacy: .public)"
      )
      windows[screenID]?.show()
    }
  }

  private func shouldHideInFullscreen(for screen: NSScreen, screenID: String) -> Bool {
    guard skylightAttachedScreenIDs.contains(screenID) else {
      return false
    }

    guard let spaceManager else {
      return false
    }

    return spaceManager.isFullscreen(screen: screen)
  }

  private func resolvedScreens(scope: CustomMenubarDisplayScope) -> [NSScreen] {
    // Gizmo currently renders the custom menubar only on the primary display.
    let _ = scope

    if let primaryScreen = NSScreen.screens.first {
      return [primaryScreen]
    }

    return []
  }

  private func screenIdentifier(_ screen: NSScreen) -> String {
    if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return number.stringValue
    }

    return UUID().uuidString
  }

  private func workspaceTapHandler() -> (String) -> Void {
    { [weak self] workspaceName in
      self?.onWorkspaceSelection?(workspaceName)
    }
  }
}
