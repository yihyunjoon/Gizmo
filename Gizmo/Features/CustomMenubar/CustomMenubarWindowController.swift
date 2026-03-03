import AppKit
import SwiftUI

@MainActor
final class CustomMenubarWindowController: NSWindowController {
  private(set) var screen: NSScreen
  private let hostingController: NSHostingController<CustomMenubarRootView>

  init(
    screen: NSScreen,
    model: CustomMenubarModel,
    config: CustomMenubarConfig,
    onWorkspaceTap: @escaping (String) -> Void
  ) {
    self.screen = screen
    self.hostingController = NSHostingController(
      rootView: CustomMenubarRootView(
        model: model,
        onWorkspaceTap: onWorkspaceTap
      )
    )
    hostingController.sizingOptions = []

    let window = CustomMenubarWindow(screen: screen, config: config)

    super.init(window: window)
    window.isReleasedWhenClosed = false
    window.contentViewController = hostingController

    update(
      screen: screen,
      model: model,
      config: config,
      onWorkspaceTap: onWorkspaceTap
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func update(
    screen: NSScreen,
    model: CustomMenubarModel,
    config: CustomMenubarConfig,
    onWorkspaceTap: @escaping (String) -> Void
  ) {
    self.screen = screen

    guard let window else { return }

    let nextFrame = CustomMenubarWindow.frame(
      for: screen,
      height: CGFloat(config.height),
      position: config.position
    )

    window.level = CustomMenubarWindow.renderLevel
    hostingController.rootView = CustomMenubarRootView(
      model: model,
      onWorkspaceTap: onWorkspaceTap
    )
    window.setFrame(nextFrame, display: true)
  }

  func show() {
    guard let window else { return }
    window.orderFrontRegardless()
  }

  func hide() {
    window?.orderOut(nil)
  }
}
