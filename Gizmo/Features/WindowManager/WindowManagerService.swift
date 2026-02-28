import AppKit
import Observation

enum WindowTileAction: String, CaseIterable {
  case leftHalf
  case rightHalf
  case placeCenter

  var commandID: String {
    switch self {
    case .leftHalf:
      return "tile-left-half"
    case .rightHalf:
      return "tile-right-half"
    case .placeCenter:
      return "place-center"
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

  // MARK: - Initialization

  init(permissionService: AccessibilityPermissionService) {
    self.permissionService = permissionService
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

    let resolvedWindowElement =
      preferredWindowElement?.frame?.isNull == false
      ? preferredWindowElement
      : AXUIElement.focusedWindowElement()

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

    let targetVisibleFrame = targetScreen.visibleFrame
    let targetFrame = targetFrame(for: action, in: targetVisibleFrame)
    let targetAXFrame = targetFrame.screenFlipped

    guard windowElement.setFrame(targetAXFrame) else {
      return .failure(.applyFailed)
    }

    return .success(())
  }

  // MARK: - Private

  private func targetFrame(
    for action: WindowTileAction,
    in visibleFrame: CGRect
  ) -> CGRect {
    switch action {
    case .leftHalf:
      let halfWidth = floor(visibleFrame.width / 2.0)
      return CGRect(
        x: visibleFrame.minX,
        y: visibleFrame.minY,
        width: halfWidth,
        height: visibleFrame.height
      )
    case .rightHalf:
      let halfWidth = floor(visibleFrame.width / 2.0)
      return CGRect(
        x: visibleFrame.maxX - halfWidth,
        y: visibleFrame.minY,
        width: halfWidth,
        height: visibleFrame.height
      )
    case .placeCenter:
      let targetWidth = max(1, floor(visibleFrame.width * 0.6))
      let targetHeight = max(1, floor(visibleFrame.height * 0.8))
      return CGRect(
        x: floor(visibleFrame.midX - (targetWidth / 2)),
        y: floor(visibleFrame.midY - (targetHeight / 2)),
        width: targetWidth,
        height: targetHeight
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
}
