import Foundation

enum LauncherAction: Equatable {
  case tile(WindowTileAction)
  case workspaceFocus(String)
  case workspaceBackAndForth
  case moveFocusedWindowToWorkspace(String)
  case launchApplication(LauncherApplicationTarget)
}

struct LauncherApplicationTarget: Codable, Equatable {
  let stableID: String
  let displayName: String
  let bundleIdentifier: String?
  let bundleURL: URL

  var fileName: String {
    bundleURL.deletingPathExtension().lastPathComponent
  }
}

enum LauncherCommandError: Error, Equatable, LocalizedError {
  case windowManager(WindowManagerError)
  case workspace(WorkspaceError)
  case appLaunch(AppLaunchError)

  var errorDescription: String? {
    switch self {
    case .windowManager(let error):
      return error.errorDescription
    case .workspace(let error):
      return error.errorDescription
    case .appLaunch(let error):
      return error.errorDescription
    }
  }

  var isAccessibilityPermissionError: Bool {
    switch self {
    case .windowManager(let error):
      return error == .permissionDenied
    case .workspace(let error):
      return error == .permissionDenied
    case .appLaunch:
      return false
    }
  }
}

enum AppLaunchError: Error, Equatable, LocalizedError {
  case appNotFound
  case openFailed

  var errorDescription: String? {
    switch self {
    case .appNotFound:
      return String(localized: "The app is no longer available.")
    case .openFailed:
      return String(localized: "Failed to launch the app.")
    }
  }
}

struct LauncherCommand: Identifiable, Equatable {
  let id: String
  let title: String
  let keywords: [String]
  let action: LauncherAction

  static func makeAll(
    workspaceNames: [String],
    applicationTargets: [LauncherApplicationTarget] = []
  ) -> [LauncherCommand] {
    makeTileCommands()
      + makeWorkspaceFocusCommands(workspaceNames: workspaceNames)
      + [makeWorkspaceBackAndForthCommand()]
      + makeMoveFocusedWindowCommands(workspaceNames: workspaceNames)
      + makeAppLaunchCommands(applicationTargets: applicationTargets)
  }

  private static func makeTileCommands() -> [LauncherCommand] {
    [
      LauncherCommand(
        id: WindowTileAction.leftHalf.commandID,
        title: WindowTileAction.leftHalf.commandTitle,
        keywords: ["tile", "left", "half", "window"],
        action: .tile(.leftHalf)
      ),
      LauncherCommand(
        id: WindowTileAction.rightHalf.commandID,
        title: WindowTileAction.rightHalf.commandTitle,
        keywords: ["tile", "right", "half", "window"],
        action: .tile(.rightHalf)
      ),
      LauncherCommand(
        id: WindowTileAction.placeCenter.commandID,
        title: WindowTileAction.placeCenter.commandTitle,
        keywords: ["place", "center", "window", "resize", "middle"],
        action: .tile(.placeCenter)
      ),
      LauncherCommand(
        id: WindowTileAction.fullScreen.commandID,
        title: WindowTileAction.fullScreen.commandTitle,
        keywords: ["fill", "full", "screen", "maximize", "window"],
        action: .tile(.fullScreen)
      ),
    ]
  }

  private static func makeWorkspaceFocusCommands(
    workspaceNames: [String]
  ) -> [LauncherCommand] {
    workspaceNames.map { workspaceName in
      LauncherCommand(
        id: "workspace-focus-\(workspaceName)",
        title: String(localized: "Switch to Workspace \(workspaceName)"),
        keywords: ["workspace", "switch", "focus", workspaceName],
        action: .workspaceFocus(workspaceName)
      )
    }
  }

  private static func makeWorkspaceBackAndForthCommand() -> LauncherCommand {
    LauncherCommand(
      id: "workspace-back-and-forth",
      title: String(localized: "Workspace Back and Forth"),
      keywords: ["workspace", "back", "forth", "previous", "toggle"],
      action: .workspaceBackAndForth
    )
  }

  private static func makeMoveFocusedWindowCommands(
    workspaceNames: [String]
  ) -> [LauncherCommand] {
    workspaceNames.map { workspaceName in
      LauncherCommand(
        id: "workspace-move-focused-window-\(workspaceName)",
        title: String(localized: "Move Focused Window to Workspace \(workspaceName)"),
        keywords: ["workspace", "move", "focused", "window", workspaceName],
        action: .moveFocusedWindowToWorkspace(workspaceName)
      )
    }
  }

  private static func makeAppLaunchCommands(
    applicationTargets: [LauncherApplicationTarget]
  ) -> [LauncherCommand] {
    applicationTargets.map { target in
      let keywordCandidates: [String?] = [
        "app",
        "open",
        "launch",
        target.displayName,
        target.fileName,
        target.bundleIdentifier,
      ]
      let keywords = keywordCandidates
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      return LauncherCommand(
        id: "app-launch-\(target.stableID)",
        title: target.displayName,
        keywords: keywords,
        action: .launchApplication(target)
      )
    }
  }
}
