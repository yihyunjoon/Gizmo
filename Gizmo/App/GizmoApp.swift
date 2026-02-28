import AppKit
import SwiftData
import SwiftUI

@main
struct GizmoApp: App {
  @State private var appEnvironment = AppEnvironment()
  private let bootstrap: AppBootstrap

  init() {
    self.bootstrap = AppBootstrap()
  }

  var body: some Scene {
    WindowGroup(id: "main") {
      GizmoSplitView()
        .frame(minWidth: 900, minHeight: 550)
        .onKeyPress { _ in .handled }
        .background {
          ZStack {
            MainWindowOpenActionRegistrar(
              launcherPanelService: bootstrap.launcherPanelService
            )
            MainWindowIdentityRegistrar()
              .frame(width: 0, height: 0)
          }
        }
        .environment(bootstrap.configStore)
        .environment(appEnvironment.permissionService)
        .environment(appEnvironment.monitorService)
        .environment(bootstrap.accessibilityPermissionService)
        .environment(bootstrap.windowManagerService)
        .onAppear {
          appEnvironment.configureMonitoring(
            container: bootstrap.sharedModelContainer,
            shouldAutoStart: bootstrap.configStore.active.keystats.autoStartMonitoring
          )
        }
        .onChange(of: bootstrap.configStore.active.keystats.autoStartMonitoring) {
          _, shouldAutoStart in
          appEnvironment.applyMonitoringPolicy(shouldAutoStart: shouldAutoStart)
        }
        .onChange(of: appEnvironment.permissionService.isGranted) { _, isGranted in
          appEnvironment.handlePermissionChange(
            isGranted,
            shouldAutoStart: bootstrap.configStore.active.keystats.autoStartMonitoring
          )
        }
    }
    .modelContainer(bootstrap.sharedModelContainer)
    .defaultSize(width: 900, height: 550)

    MenuBarExtra(
      String(localized: "Gizmo"),
      systemImage: "keyboard"
    ) {
      MenuBarView()
        .environment(bootstrap.configStore)
    }
  }
}

private struct MainWindowOpenActionRegistrar: View {
  @Environment(\.openWindow) private var openWindow

  let launcherPanelService: LauncherPanelService

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        launcherPanelService.onOpenMainWindowRequest = { [openWindow] targetCenter in
          openWindow(id: "main")
          DispatchQueue.main.async {
            bringMainWindowToFront(centeredAt: targetCenter, remainingAttempts: 4)
          }
        }
      }
  }

  private func bringMainWindowToFront(
    centeredAt targetCenter: CGPoint?,
    remainingAttempts: Int
  ) {
    guard let window = resolveMainWindow() else {
      guard remainingAttempts > 0 else { return }

      DispatchQueue.main.async {
        bringMainWindowToFront(
          centeredAt: targetCenter,
          remainingAttempts: remainingAttempts - 1
        )
      }
      return
    }

    centerWindow(window, at: targetCenter)

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }

    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func resolveMainWindow() -> NSWindow? {
    if let taggedCandidate = NSApplication.shared.orderedWindows.first(where: isTaggedMainWindow(_:)) {
      return taggedCandidate
    }

    if let taggedCandidate = NSApplication.shared.windows.first(where: isTaggedMainWindow(_:)) {
      return taggedCandidate
    }

    if let orderedCandidate = NSApplication.shared.orderedWindows.first(where: isFallbackMainWindow(_:)) {
      return orderedCandidate
    }

    return NSApplication.shared.windows.first(where: isFallbackMainWindow(_:))
  }

  private func isTaggedMainWindow(_ window: NSWindow) -> Bool {
    window.identifier == MainWindowIdentity.identifier
  }

  private func isFallbackMainWindow(_ window: NSWindow) -> Bool {
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

private struct MainWindowIdentityRegistrar: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)

    DispatchQueue.main.async {
      view.window?.identifier = MainWindowIdentity.identifier
    }

    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      nsView.window?.identifier = MainWindowIdentity.identifier
    }
  }
}
