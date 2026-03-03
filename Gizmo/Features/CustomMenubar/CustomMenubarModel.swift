import AppKit
import Foundation
import Observation

protocol CustomMenubarPresenting {
  func start()
  func stop()
  func apply(config: CustomMenubarConfig)
  func reconfigureForDisplayChanges()
}

enum CustomMenubarRuntimeError: Error, LocalizedError {
  case bridgeUnavailable
  case symbolNotFound(String)
  case windowBindFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .bridgeUnavailable:
      return "Could not open SkyLight framework handle."
    case .symbolNotFound(let symbol):
      return "SkyLight symbol not found: \(symbol)."
    case .windowBindFailed(let code):
      return "Failed to bind custom menubar window into SkyLight managed space (code: \(code))."
    }
  }
}

@MainActor
@Observable
final class CustomMenubarModel {
  static let defaultWorkspaceNames: [String] = WorkspaceConfig.defaultNames

  private(set) var clockText = ""
  private(set) var frontAppName = ""
  private(set) var workspaceNames: [String] = defaultWorkspaceNames
  private(set) var focusedWorkspaceName: String = defaultWorkspaceNames.first ?? "1"
  private(set) var config: CustomMenubarConfig = .default

  private var clockTimer: Timer?
  private var frontAppObserver: NSObjectProtocol?

  func start() {
    observeFrontApplicationIfNeeded()
    updateFrontAppName()
    configureClockTimerIfNeeded()
  }

  func stop() {
    if let frontAppObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(frontAppObserver)
      self.frontAppObserver = nil
    }

    clockTimer?.invalidate()
    clockTimer = nil
  }

  func apply(config: CustomMenubarConfig) {
    self.config = config
    updateFrontAppName()
    configureClockTimerIfNeeded()
  }

  func hasWidget(_ widget: CustomMenubarWidget) -> Bool {
    config.widgets.contains(widget)
  }

  func isFocusedWorkspace(_ workspaceName: String) -> Bool {
    focusedWorkspaceName == workspaceName
  }

  func focusWorkspace(_ workspaceName: String) {
    guard workspaceNames.contains(workspaceName) else { return }
    focusedWorkspaceName = workspaceName
  }

  func updateWorkspaceState(
    names: [String],
    focusedWorkspaceName: String
  ) {
    workspaceNames = names.isEmpty ? Self.defaultWorkspaceNames : names
    self.focusedWorkspaceName = workspaceNames.contains(focusedWorkspaceName)
      ? focusedWorkspaceName
      : (workspaceNames.first ?? Self.defaultWorkspaceNames[0])
  }

  private func observeFrontApplicationIfNeeded() {
    guard frontAppObserver == nil else { return }

    frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateFrontAppName()
      }
    }
  }

  private func configureClockTimerIfNeeded() {
    let shouldRenderClock = hasWidget(.clock)

    if !shouldRenderClock {
      clockTimer?.invalidate()
      clockTimer = nil
      clockText = ""
      return
    }

    updateClockText()

    guard clockTimer == nil else { return }

    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateClockText()
      }
    }

    RunLoop.main.add(timer, forMode: .common)
    clockTimer = timer
  }

  private func updateClockText() {
    guard hasWidget(.clock) else {
      clockText = ""
      return
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = config.clock24h ? "HH:mm:ss" : "hh:mm:ss a"
    clockText = formatter.string(from: Date())
  }

  private func updateFrontAppName() {
    guard hasWidget(.frontApp) else {
      frontAppName = ""
      return
    }

    frontAppName = NSWorkspace.shared.frontmostApplication?.localizedName
      ?? String(localized: "Unknown App")
  }
}
