import Foundation

struct LauncherCommand: Identifiable, Equatable {
  let id: String
  let title: String
  let keywords: [String]
  let action: WindowTileAction

  static let all: [LauncherCommand] = [
    LauncherCommand(
      id: WindowTileAction.leftHalf.commandID,
      title: WindowTileAction.leftHalf.commandTitle,
      keywords: ["tile", "left", "half", "window"],
      action: .leftHalf
    ),
    LauncherCommand(
      id: WindowTileAction.rightHalf.commandID,
      title: WindowTileAction.rightHalf.commandTitle,
      keywords: ["tile", "right", "half", "window"],
      action: .rightHalf
    ),
    LauncherCommand(
      id: WindowTileAction.placeCenter.commandID,
      title: WindowTileAction.placeCenter.commandTitle,
      keywords: ["place", "center", "window", "resize", "middle"],
      action: .placeCenter
    ),
  ]
}
