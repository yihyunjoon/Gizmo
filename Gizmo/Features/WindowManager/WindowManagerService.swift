import AppKit
import Observation

enum WindowTileAction: String, CaseIterable {
  case leftHalf
  case rightHalf
  case placeCenter
  case fullScreen

  var commandID: String {
    switch self {
    case .leftHalf:
      return "tile-left-half"
    case .rightHalf:
      return "tile-right-half"
    case .placeCenter:
      return "place-center"
    case .fullScreen:
      return "tile-full-screen"
    }
  }

  var commandTitle: String {
    switch self {
    case .leftHalf:
      return String(localized: "Tile left half")
    case .rightHalf:
      return String(localized: "Tile right half")
    case .placeCenter:
      return String(localized: "Place center")
    case .fullScreen:
      return String(localized: "Fill screen")
    }
  }
}

enum WindowManagerError: Error, Equatable, LocalizedError {
  case permissionDenied
  case noFocusedWindow
  case noUsableScreen
  case applyFailed

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return String(localized: "Accessibility permission is required.")
    case .noFocusedWindow:
      return String(localized: "No focused window.")
    case .noUsableScreen:
      return String(localized: "No usable screen found.")
    case .applyFailed:
      return String(localized: "Failed to move window.")
    }
  }
}

@Observable
@MainActor
final class WindowManagerService {
  // MARK: - Properties

  private let permissionService: AccessibilityPermissionService
  private let customMenubarConfigProvider: @MainActor () -> CustomMenubarConfig
  private let workspaceConfigProvider: @MainActor () -> WorkspaceConfig
  private let gapsConfigProvider: @MainActor () -> WindowManagerGapsConfig
  private let fallbackWindowElementProvider: @MainActor () -> AXUIElement?

  // MARK: - Initialization

  init(
    permissionService: AccessibilityPermissionService,
    customMenubarConfigProvider: @escaping @MainActor () -> CustomMenubarConfig = { .default },
    workspaceConfigProvider: @escaping @MainActor () -> WorkspaceConfig = { .default },
    gapsConfigProvider: @escaping @MainActor () -> WindowManagerGapsConfig = { .default },
    fallbackWindowElementProvider: @escaping @MainActor () -> AXUIElement? = { nil }
  ) {
    self.permissionService = permissionService
    self.customMenubarConfigProvider = customMenubarConfigProvider
    self.workspaceConfigProvider = workspaceConfigProvider
    self.gapsConfigProvider = gapsConfigProvider
    self.fallbackWindowElementProvider = fallbackWindowElementProvider
  }

  // MARK: - Public API

  func execute(
    _ action: WindowTileAction,
    preferredWindowElement: AXUIElement? = nil
  ) -> Result<Void, WindowManagerError> {
    permissionService.refresh()

    guard permissionService.isGranted else {
      return .failure(.permissionDenied)
    }

    let resolvedWindowElement = resolveWindowElement(
      preferredWindowElement: preferredWindowElement
    )

    guard
      let windowElement = resolvedWindowElement,
      let focusedWindowAXFrame = windowElement.frame,
      !focusedWindowAXFrame.isNull
    else {
      return .failure(.noFocusedWindow)
    }

    let focusedWindowFrame = focusedWindowAXFrame.screenFlipped

    guard let targetScreen = screenContaining(windowFrame: focusedWindowFrame) else {
      return .failure(.noUsableScreen)
    }

    let baseVisibleFrame = targetVisibleFrame(for: targetScreen)
    let gapsConfig = gapsConfigProvider()
    let usableVisibleFrame = WindowManagerLayoutCalculator.applyOuterGaps(
      to: baseVisibleFrame,
      outerGaps: gapsConfig.outer
    )
    guard usableVisibleFrame.width >= 1, usableVisibleFrame.height >= 1 else {
      return .failure(.noUsableScreen)
    }

    let targetFrame = WindowManagerLayoutCalculator.targetFrame(
      for: action,
      in: usableVisibleFrame,
      innerHorizontalGap: CGFloat(gapsConfig.inner.horizontal)
    )
    let targetAXFrame = targetFrame.screenFlipped

    guard windowElement.setFrame(targetAXFrame) else {
      return .failure(.applyFailed)
    }

    return .success(())
  }

  // MARK: - Private

  private func targetVisibleFrame(for screen: NSScreen) -> CGRect {
    let baseVisibleFrame = screen.visibleFrame
    let customMenubarConfig = customMenubarConfigProvider()

    guard customMenubarConfig.enabled else {
      return baseVisibleFrame
    }

    guard shouldReserveCustomMenubarSpace(on: screen) else {
      return baseVisibleFrame
    }

    let reservedHeight = min(
      CGFloat(customMenubarConfig.height),
      max(0, baseVisibleFrame.height - 1)
    )

    guard reservedHeight > 0 else {
      return baseVisibleFrame
    }

    switch customMenubarConfig.position {
    case .top:
      return CGRect(
        x: baseVisibleFrame.minX,
        y: baseVisibleFrame.minY,
        width: baseVisibleFrame.width,
        height: baseVisibleFrame.height - reservedHeight
      )
    case .bottom:
      return CGRect(
        x: baseVisibleFrame.minX,
        y: baseVisibleFrame.minY + reservedHeight,
        width: baseVisibleFrame.width,
        height: baseVisibleFrame.height - reservedHeight
      )
    }
  }

  private func screenContaining(windowFrame: CGRect) -> NSScreen? {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return nil }

    if let containingScreen = screens.first(where: { $0.frame.contains(windowFrame) }) {
      return containingScreen
    }

    var bestScreen: NSScreen?
    var bestRatio: CGFloat = 0

    for screen in screens {
      let ratio = windowFrame.intersectionRatio(with: screen.frame)
      if ratio > bestRatio {
        bestRatio = ratio
        bestScreen = screen
      }
    }

    return bestScreen ?? NSScreen.main
  }

  private func shouldReserveCustomMenubarSpace(
    on screen: NSScreen
  ) -> Bool {
    let workspaceConfig = workspaceConfigProvider()

    switch workspaceConfig.mode {
    case .primaryOnly, .unified:
      guard let primaryScreen = NSScreen.screens.first else { return false }
      return screenIdentifier(screen) == screenIdentifier(primaryScreen)
    case .perDisplay:
      guard let displayRole = displayRole(for: screen) else { return false }

      return switch displayRole {
      case .primary:
        true
      case .secondary:
        !workspaceConfig.secondaryNames.isEmpty
      }
    }
  }

  private func screenIdentifier(_ screen: NSScreen) -> String {
    if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return number.stringValue
    }

    return UUID().uuidString
  }

  private func displayRole(for screen: NSScreen) -> WorkspaceDisplayRole? {
    let screens = NSScreen.screens
    guard let screenIndex = screens.firstIndex(where: { screenIdentifier($0) == screenIdentifier(screen) }) else {
      return nil
    }

    return switch screenIndex {
    case 0:
      .primary
    case 1:
      .secondary
    default:
      nil
    }
  }

  private func resolveWindowElement(
    preferredWindowElement: AXUIElement?
  ) -> AXUIElement? {
    if let preferredWindowElement = validatedWindowElement(preferredWindowElement) {
      return preferredWindowElement
    }

    let focusedWindowElement = validatedWindowElement(AXUIElement.focusedWindowElement())
    if let focusedWindowElement, !belongsToCurrentProcess(focusedWindowElement) {
      return focusedWindowElement
    }

    if let fallbackWindowElement = validatedWindowElement(fallbackWindowElementProvider()) {
      return fallbackWindowElement
    }

    return focusedWindowElement
  }

  private func validatedWindowElement(_ element: AXUIElement?) -> AXUIElement? {
    guard let element else { return nil }
    guard let frame = element.frame, !frame.isNull else { return nil }
    return element
  }

  private func belongsToCurrentProcess(_ element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return false }
    return pid == ProcessInfo.processInfo.processIdentifier
  }
}

struct WindowManagerLayoutCalculator {
  static func applyOuterGaps(
    to frame: CGRect,
    outerGaps: WindowManagerOuterGaps
  ) -> CGRect {
    let left = CGFloat(outerGaps.left)
    let top = CGFloat(outerGaps.top)
    let right = CGFloat(outerGaps.right)
    let bottom = CGFloat(outerGaps.bottom)

    return CGRect(
      x: frame.minX + left,
      y: frame.minY + bottom,
      width: frame.width - left - right,
      height: frame.height - top - bottom
    )
  }

  static func targetFrame(
    for action: WindowTileAction,
    in visibleFrame: CGRect,
    innerHorizontalGap: CGFloat
  ) -> CGRect {
    switch action {
    case .leftHalf:
      let availableWidth = visibleFrame.width
      let seam = min(innerHorizontalGap, max(0, availableWidth - 2))
      let leftWidth = floor((availableWidth - seam) / 2)
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: leftWidth,
        height: visibleFrame.height
      )
    case .rightHalf:
      let availableWidth = visibleFrame.width
      let seam = min(innerHorizontalGap, max(0, availableWidth - 2))
      let leftWidth = floor((availableWidth - seam) / 2)
      let rightWidth = availableWidth - seam - leftWidth
      return CGRect(
        x: visibleFrame.minX + leftWidth + seam,
        y: visibleFrame.minY,
        width: rightWidth,
        height: visibleFrame.height
      )
    case .placeCenter:
      let targetWidth = max(1, floor(visibleFrame.width / 2))
      return CGRect(
        x: floor(visibleFrame.midX - (targetWidth / 2)),
        y: visibleFrame.minY,
        width: targetWidth,
        height: visibleFrame.height
      )
    case .fullScreen:
      return visibleFrame
    }
  }
}
