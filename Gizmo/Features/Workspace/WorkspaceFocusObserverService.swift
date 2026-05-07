import AppKit
import ApplicationServices

@MainActor
final class WorkspaceFocusObserverService {
  var onFocusedWindowChanged: (() -> Void)?
  var onActiveApplicationChanged: ((pid_t) -> Void)?
  var onObservedWindowDestroyed: (() -> Void)?

  private let permissionService: AccessibilityPermissionService

  private var isRunning = false
  private var activeApplicationObserver: NSObjectProtocol?
  private var axObserver: AXObserver?
  private var observedPID: pid_t?
  private var didScheduleFocusChange = false
  private var observedWindowElements: [AXUIElement] = []
  private var lastFocusedExternalWindowElement: AXUIElement?

  init(permissionService: AccessibilityPermissionService) {
    self.permissionService = permissionService
  }

  func start() {
    guard !isRunning else { return }

    isRunning = true
    observeActiveApplicationIfNeeded()
    refreshObserverForFrontmostApplication()
    scheduleFocusChange()
  }

  func preferredWindowElement() -> AXUIElement? {
    lastFocusedExternalWindowElement
  }

  func stop() {
    guard isRunning else { return }

    isRunning = false
    removeActiveApplicationObserver()
    removeAXObserver()
    didScheduleFocusChange = false
  }

  private func observeActiveApplicationIfNeeded() {
    guard activeApplicationObserver == nil else { return }

    activeApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let processIdentifier =
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
        .processIdentifier

      Task { @MainActor [weak self] in
        self?.handleActiveApplicationDidChange(processIdentifier)
      }
    }
  }

  private func removeActiveApplicationObserver() {
    if let activeApplicationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activeApplicationObserver)
      self.activeApplicationObserver = nil
    }
  }

  private func handleActiveApplicationDidChange(_ processIdentifier: pid_t?) {
    guard isRunning else { return }

    refreshObserver(for: processIdentifier)
    if let processIdentifier {
      onActiveApplicationChanged?(processIdentifier)
    }
    scheduleFocusChange()
  }

  private func refreshObserverForFrontmostApplication() {
    refreshObserver(for: NSWorkspace.shared.frontmostApplication?.processIdentifier)
  }

  private func refreshObserver(for pid: pid_t?) {
    permissionService.refresh()

    guard permissionService.isGranted else {
      removeAXObserver()
      return
    }

    guard let pid else {
      removeAXObserver()
      return
    }

    guard pid != ProcessInfo.processInfo.processIdentifier else {
      removeAXObserver()
      return
    }

    guard observedPID != pid else { return }

    removeAXObserver()

    var observer: AXObserver?
    let createResult = AXObserverCreate(
      pid,
      { _, element, notification, refcon in
        guard let refcon else { return }

        let service = Unmanaged<WorkspaceFocusObserverService>
          .fromOpaque(refcon)
          .takeUnretainedValue()

        Task { @MainActor in
          service.handleAXNotification(
            element: element,
            notification: notification as String
          )
        }
      },
      &observer
    )

    guard createResult == .success, let observer else { return }

    let appElement = AXUIElementCreateApplication(pid)
    let observerContext = Unmanaged.passUnretained(self).toOpaque()

    let focusedWindowResult = AXObserverAddNotification(
      observer,
      appElement,
      kAXFocusedWindowChangedNotification as CFString,
      observerContext
    )

    let mainWindowResult = AXObserverAddNotification(
      observer,
      appElement,
      kAXMainWindowChangedNotification as CFString,
      observerContext
    )

    let didRegisterNotification =
      Self.isNotificationRegistered(focusedWindowResult)
      || Self.isNotificationRegistered(mainWindowResult)

    guard didRegisterNotification else { return }

    updateObservedWindowNotifications(
      observer: observer,
      appElement: appElement,
      observerContext: observerContext
    )
    updateLastFocusedExternalWindow(from: appElement)

    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(observer),
      .defaultMode
    )

    axObserver = observer
    observedPID = pid
  }

  private func handleAXNotification(
    element: AXUIElement,
    notification: String
  ) {
    guard isRunning else { return }

    switch notification {
    case String(kAXFocusedWindowChangedNotification),
      String(kAXMainWindowChangedNotification):
      refreshObservedWindowNotifications()
      refreshLastFocusedExternalWindow()
      scheduleFocusChange()
    case String(kAXUIElementDestroyedNotification):
      observedWindowElements.removeAll { CFEqual($0, element) }
      if let lastFocusedExternalWindowElement, CFEqual(lastFocusedExternalWindowElement, element) {
        self.lastFocusedExternalWindowElement = nil
      }
      scheduleObservedWindowDestroyed()
    default:
      break
    }
  }

  private func removeAXObserver() {
    removeObservedWindowNotifications()

    guard let axObserver else {
      observedPID = nil
      return
    }

    CFRunLoopRemoveSource(
      CFRunLoopGetMain(),
      AXObserverGetRunLoopSource(axObserver),
      .defaultMode
    )

    self.axObserver = nil
    observedPID = nil
  }

  private func refreshObservedWindowNotifications() {
    guard let axObserver, let observedPID else { return }

    let appElement = AXUIElementCreateApplication(observedPID)
    let observerContext = Unmanaged.passUnretained(self).toOpaque()
    updateObservedWindowNotifications(
      observer: axObserver,
      appElement: appElement,
      observerContext: observerContext
    )
  }

  private func refreshLastFocusedExternalWindow() {
    guard let observedPID else { return }
    let appElement = AXUIElementCreateApplication(observedPID)
    updateLastFocusedExternalWindow(from: appElement)
  }

  private func updateObservedWindowNotifications(
    observer: AXObserver,
    appElement: AXUIElement,
    observerContext: UnsafeMutableRawPointer
  ) {
    let candidateWindows = currentObservedWindows(for: appElement)

    removeObservedWindowNotifications()

    var trackedWindows: [AXUIElement] = []
    for window in candidateWindows {
      let addResult = AXObserverAddNotification(
        observer,
        window,
        kAXUIElementDestroyedNotification as CFString,
        observerContext
      )
      guard Self.isNotificationRegistered(addResult) else { continue }
      trackedWindows.append(window)
    }

    observedWindowElements = trackedWindows
  }

  private func removeObservedWindowNotifications() {
    guard let axObserver else {
      observedWindowElements = []
      return
    }

    for window in observedWindowElements {
      _ = AXObserverRemoveNotification(
        axObserver,
        window,
        kAXUIElementDestroyedNotification as CFString
      )
    }
    observedWindowElements = []
  }

  private func currentObservedWindows(for appElement: AXUIElement) -> [AXUIElement] {
    var windows: [AXUIElement] = []

    if let focusedWindow = copyAXElement(
      attribute: kAXFocusedWindowAttribute as CFString,
      from: appElement
    ) {
      windows.append(focusedWindow)
    }

    if let mainWindow = copyAXElement(
      attribute: kAXMainWindowAttribute as CFString,
      from: appElement
    ),
      !windows.contains(where: { CFEqual($0, mainWindow) })
    {
      windows.append(mainWindow)
    }

    return windows
  }

  private func updateLastFocusedExternalWindow(from appElement: AXUIElement) {
    if let focusedWindow = copyAXElement(
      attribute: kAXFocusedWindowAttribute as CFString,
      from: appElement
    ) {
      lastFocusedExternalWindowElement = focusedWindow
      return
    }

    if let mainWindow = copyAXElement(
      attribute: kAXMainWindowAttribute as CFString,
      from: appElement
    ) {
      lastFocusedExternalWindowElement = mainWindow
      return
    }

    lastFocusedExternalWindowElement = nil
  }

  private func copyAXElement(
    attribute: CFString,
    from element: AXUIElement
  ) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    guard let value else { return nil }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }

    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private func scheduleFocusChange() {
    guard !didScheduleFocusChange else { return }

    didScheduleFocusChange = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      self.didScheduleFocusChange = false
      guard self.isRunning else { return }

      self.onFocusedWindowChanged?()
    }
  }

  private func scheduleObservedWindowDestroyed() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self else { return }
      guard self.isRunning else { return }

      self.onObservedWindowDestroyed?()
      self.onFocusedWindowChanged?()
    }
  }

  private static func isNotificationRegistered(_ result: AXError) -> Bool {
    result == .success || result == .notificationAlreadyRegistered
  }
}
