import AppKit
import KeyboardShortcuts

struct GizmoConfig: Equatable {
  var configVersion: Int
  var launcher: LauncherConfig
  var customMenubar: CustomMenubarConfig
  var workspace: WorkspaceConfig
  var gaps: WindowManagerGapsConfig
  var keystats: KeystatsConfig

  static let supportedConfigVersion = 1

  static let `default` = GizmoConfig(
    configVersion: supportedConfigVersion,
    launcher: .default,
    customMenubar: .default,
    workspace: .default,
    gaps: .default,
    keystats: .default
  )
}

struct WorkspaceConfig: Equatable {
  var enabled: Bool
  var names: [String]
  var hideStrategy: WorkspaceHideStrategy

  static let defaultNames: [String] = ["1", "2", "3", "4", "5"]

  static let `default` = WorkspaceConfig(
    enabled: true,
    names: defaultNames,
    hideStrategy: .cornerOffscreen
  )
}

enum WorkspaceHideStrategy: String, CaseIterable, Equatable {
  case cornerOffscreen = "corner_offscreen"
}

struct LauncherConfig: Equatable {
  var display: LauncherDisplay
  var forceEnglishInputSource: Bool
  var globalHotkey: HotkeyConfig

  static let `default` = LauncherConfig(
    display: .activeWindow,
    forceEnglishInputSource: false,
    globalHotkey: .default
  )
}

enum LauncherDisplay: String, CaseIterable, Equatable {
  case primary
  case mouse
  case activeWindow = "active_window"
}

struct HotkeyConfig: Equatable {
  var key: String
  var modifiers: [HotkeyModifier]

  static let `default` = HotkeyConfig(
    key: "space",
    modifiers: [.command, .shift]
  )

  var keyboardShortcut: KeyboardShortcuts.Shortcut? {
    guard let keyboardKey = KeyboardShortcuts.Key.fromConfigKey(key) else {
      return nil
    }

    return .init(
      keyboardKey,
      modifiers: modifiers.reduce(into: NSEvent.ModifierFlags()) {
        $0.insert($1.eventFlag)
      }
    )
  }

  var descriptionText: String {
    guard let keyboardShortcut else {
      let mods = modifiers.map(\.rawValue).joined(separator: "+")
      return mods.isEmpty ? key : "\(mods)+\(key)"
    }

    return keyboardShortcut.description
  }
}

enum HotkeyModifier: String, CaseIterable, Equatable {
  case command
  case shift
  case option
  case control
  case function

  var eventFlag: NSEvent.ModifierFlags {
    switch self {
    case .command:
      return .command
    case .shift:
      return .shift
    case .option:
      return .option
    case .control:
      return .control
    case .function:
      return .function
    }
  }
}

struct KeystatsConfig: Equatable {
  var autoStartMonitoring: Bool

  static let `default` = KeystatsConfig(
    autoStartMonitoring: true
  )
}

struct WindowManagerGapsConfig: Equatable {
  var inner: WindowManagerInnerGaps
  var outer: WindowManagerOuterGaps

  static let `default` = WindowManagerGapsConfig(
    inner: .default,
    outer: .default
  )
}

struct WindowManagerInnerGaps: Equatable {
  var horizontal: Double
  var vertical: Double

  static let `default` = WindowManagerInnerGaps(
    horizontal: 0,
    vertical: 0
  )
}

struct WindowManagerOuterGaps: Equatable {
  var left: Double
  var top: Double
  var right: Double
  var bottom: Double

  static let `default` = WindowManagerOuterGaps(
    left: 0,
    top: 0,
    right: 0,
    bottom: 0
  )
}

struct CustomMenubarConfig: Equatable {
  var enabled: Bool
  var border: Bool
  var displayScope: CustomMenubarDisplayScope
  var position: CustomMenubarPosition
  var height: Double
  var widgets: [CustomMenubarWidget]
  var backgroundOpacity: Double
  var horizontalPadding: Double
  var clock24h: Bool

  static let `default` = CustomMenubarConfig(
    enabled: false,
    border: true,
    displayScope: .all,
    position: .bottom,
    height: 30,
    widgets: [.frontApp, .clock],
    backgroundOpacity: 0.75,
    horizontalPadding: 8,
    clock24h: true
  )
}

enum CustomMenubarDisplayScope: String, CaseIterable, Equatable {
  case all
  case active
  case primary
}

enum CustomMenubarPosition: String, CaseIterable, Equatable {
  case top
  case bottom
}

enum CustomMenubarWidget: String, CaseIterable, Equatable {
  case clock
  case frontApp = "front_app"
}

extension KeyboardShortcuts.Key {
  static func fromConfigKey(_ rawValue: String) -> Self? {
    let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    return switch key {
    case "a": .a
    case "b": .b
    case "c": .c
    case "d": .d
    case "e": .e
    case "f": .f
    case "g": .g
    case "h": .h
    case "i": .i
    case "j": .j
    case "k": .k
    case "l": .l
    case "m": .m
    case "n": .n
    case "o": .o
    case "p": .p
    case "q": .q
    case "r": .r
    case "s": .s
    case "t": .t
    case "u": .u
    case "v": .v
    case "w": .w
    case "x": .x
    case "y": .y
    case "z": .z
    case "0", "zero": .zero
    case "1", "one": .one
    case "2", "two": .two
    case "3", "three": .three
    case "4", "four": .four
    case "5", "five": .five
    case "6", "six": .six
    case "7", "seven": .seven
    case "8", "eight": .eight
    case "9", "nine": .nine
    case "space": .space
    case "return", "enter": .return
    case "tab": .tab
    case "escape", "esc": .escape
    case "up", "up_arrow": .upArrow
    case "down", "down_arrow": .downArrow
    case "left", "left_arrow": .leftArrow
    case "right", "right_arrow": .rightArrow
    case "f1": .f1
    case "f2": .f2
    case "f3": .f3
    case "f4": .f4
    case "f5": .f5
    case "f6": .f6
    case "f7": .f7
    case "f8": .f8
    case "f9": .f9
    case "f10": .f10
    case "f11": .f11
    case "f12": .f12
    case "f13": .f13
    case "f14": .f14
    case "f15": .f15
    case "f16": .f16
    case "f17": .f17
    case "f18": .f18
    case "f19": .f19
    case "f20": .f20
    default: nil
    }
  }
}
