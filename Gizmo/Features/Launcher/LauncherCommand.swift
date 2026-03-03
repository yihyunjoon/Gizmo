import Foundation

enum LauncherAction: Equatable {
  case tile(WindowTileAction)
  case workspaceFocus(String)
  case workspaceBackAndForth
  case moveFocusedWindowToWorkspace(String)
}

enum LauncherCommandError: Error, Equatable, LocalizedError {
  case windowManager(WindowManagerError)
  case workspace(WorkspaceError)

  var errorDescription: String? {
    switch self {
    case .windowManager(let error):
      return error.errorDescription
    case .workspace(let error):
      return error.errorDescription
    }
  }

  var isAccessibilityPermissionError: Bool {
    switch self {
    case .windowManager(.permissionDenied), .workspace(.permissionDenied):
      return true
    default:
      return false
    }
  }
}

struct LauncherCommand: Identifiable, Equatable {
  let id: String
  let title: String
  let keywords: [String]
  let action: LauncherAction

  static func makeAll(workspaceNames: [String]) -> [LauncherCommand] {
    makeTileCommands()
      + makeWorkspaceFocusCommands(workspaceNames: workspaceNames)
      + [makeWorkspaceBackAndForthCommand()]
      + makeMoveFocusedWindowCommands(workspaceNames: workspaceNames)
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
}
