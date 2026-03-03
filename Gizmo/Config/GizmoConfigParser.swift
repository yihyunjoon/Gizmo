import Foundation
import KeyboardShortcuts
import TOMLKit

struct GizmoConfigParser {
  func parse(_ rawToml: String) -> (config: GizmoConfig?, errors: [String]) {
    let rawTable: TOMLTable

    do {
      rawTable = try TOMLTable(string: rawToml)
    } catch let error as TOMLParseError {
      return (nil, ["syntax: \(error.debugDescription)"])
    } catch {
      return (nil, ["syntax: \(error.localizedDescription)"])
    }

    var config = GizmoConfig.default
    var errors: [String] = []

    let allowedRootKeys: Set<String> = [
      "config-version",
      "launcher",
      "custom_menubar",
      "gaps",
      "keystats",
    ]
    appendUnknownKeys(
      in: rawTable,
      allowed: allowedRootKeys,
      prefix: "",
      errors: &errors
    )

    if let versionValue = rawTable["config-version"] {
      if let version = versionValue.int {
        if version == GizmoConfig.supportedConfigVersion {
          config.configVersion = version
        } else {
          errors.append(
            "config-version: Unsupported value '\(version)'. Only \(GizmoConfig.supportedConfigVersion) is supported."
          )
        }
      } else {
        errors.append("config-version: Expected int, got \(versionValue.type)")
      }
    }

    if let launcherValue = rawTable["launcher"] {
      parseLauncher(launcherValue, config: &config, errors: &errors)
    }

    if let customMenubarValue = rawTable["custom_menubar"] {
      parseCustomMenubar(customMenubarValue, config: &config, errors: &errors)
    }

    if let gapsValue = rawTable["gaps"] {
      parseGaps(gapsValue, config: &config, errors: &errors)
    }

    if let keystatsValue = rawTable["keystats"] {
      parseKeystats(keystatsValue, config: &config, errors: &errors)
    }

    return errors.isEmpty ? (config, []) : (nil, errors)
  }

  private func parseLauncher(
    _ raw: TOMLValueConvertible,
    config: inout GizmoConfig,
    errors: inout [String]
  ) {
    guard let launcherTable = raw.table else {
      errors.append("launcher: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: launcherTable,
      allowed: ["display", "force_english_input_source", "global_hotkey"],
      prefix: "launcher",
      errors: &errors
    )

    if let displayRaw = launcherTable["display"] {
      guard let displayString = displayRaw.string else {
        errors.append("launcher.display: Expected string, got \(displayRaw.type)")
        return
      }

      guard let display = LauncherDisplay(rawValue: displayString) else {
        errors.append(
          "launcher.display: Invalid value '\(displayString)'. Allowed: primary, mouse, active_window."
        )
        return
      }

      config.launcher.display = display
    }

    if let forceEnglishRaw = launcherTable["force_english_input_source"] {
      guard let forceEnglish = forceEnglishRaw.bool else {
        errors.append(
          "launcher.force_english_input_source: Expected bool, got \(forceEnglishRaw.type)"
        )
        return
      }

      config.launcher.forceEnglishInputSource = forceEnglish
    }

    if let hotkeyRaw = launcherTable["global_hotkey"] {
      parseGlobalHotkey(
        hotkeyRaw,
        hotkey: &config.launcher.globalHotkey,
        errors: &errors
      )
    }
  }

  private func parseGlobalHotkey(
    _ raw: TOMLValueConvertible,
    hotkey: inout HotkeyConfig,
    errors: inout [String]
  ) {
    guard let hotkeyTable = raw.table else {
      errors.append("launcher.global_hotkey: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: hotkeyTable,
      allowed: ["key", "modifiers"],
      prefix: "launcher.global_hotkey",
      errors: &errors
    )

    if let keyRaw = hotkeyTable["key"] {
      guard let key = keyRaw.string else {
        errors.append("launcher.global_hotkey.key: Expected string, got \(keyRaw.type)")
        return
      }

      if KeyboardShortcuts.Key.fromConfigKey(key) == nil {
        errors.append("launcher.global_hotkey.key: Unsupported key '\(key)'.")
      } else {
        hotkey.key = key
      }
    }

    if let modifiersRaw = hotkeyTable["modifiers"] {
      guard let modifiersArray = modifiersRaw.array else {
        errors.append(
          "launcher.global_hotkey.modifiers: Expected array, got \(modifiersRaw.type)"
        )
        return
      }

      var parsedModifiers: [HotkeyModifier] = []

      for (index, value) in modifiersArray.enumerated() {
        guard let modifierValue = value.string else {
          errors.append(
            "launcher.global_hotkey.modifiers[\(index)]: Expected string, got \(value.type)"
          )
          continue
        }

        guard let modifier = HotkeyModifier(rawValue: modifierValue) else {
          errors.append(
            "launcher.global_hotkey.modifiers[\(index)]: Invalid value '\(modifierValue)'. Allowed: command, shift, option, control, function."
          )
          continue
        }

        parsedModifiers.append(modifier)
      }

      hotkey.modifiers = parsedModifiers
    }
  }

  private func parseCustomMenubar(
    _ raw: TOMLValueConvertible,
    config: inout GizmoConfig,
    errors: inout [String]
  ) {
    guard let menubarTable = raw.table else {
      errors.append("custom_menubar: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: menubarTable,
      allowed: [
        "enabled",
        "border",
        "display_scope",
        "position",
        "height",
        "widgets",
        "background_opacity",
        "horizontal_padding",
        "clock_24h",
      ],
      prefix: "custom_menubar",
      errors: &errors
    )

    if let enabledRaw = menubarTable["enabled"] {
      guard let enabled = enabledRaw.bool else {
        errors.append("custom_menubar.enabled: Expected bool, got \(enabledRaw.type)")
        return
      }

      config.customMenubar.enabled = enabled
    }

    if let borderRaw = menubarTable["border"] {
      guard let border = borderRaw.bool else {
        errors.append("custom_menubar.border: Expected bool, got \(borderRaw.type)")
        return
      }

      config.customMenubar.border = border
    }

    if let displayScopeRaw = menubarTable["display_scope"] {
      guard let displayScopeValue = displayScopeRaw.string else {
        errors.append("custom_menubar.display_scope: Expected string, got \(displayScopeRaw.type)")
        return
      }

      guard let scope = CustomMenubarDisplayScope(rawValue: displayScopeValue) else {
        errors.append(
          "custom_menubar.display_scope: Invalid value '\(displayScopeValue)'. Allowed: all, active, primary."
        )
        return
      }

      config.customMenubar.displayScope = scope
    }

    if let positionRaw = menubarTable["position"] {
      guard let positionValue = positionRaw.string else {
        errors.append("custom_menubar.position: Expected string, got \(positionRaw.type)")
        return
      }

      guard let position = CustomMenubarPosition(rawValue: positionValue) else {
        errors.append(
          "custom_menubar.position: Invalid value '\(positionValue)'. Allowed: top, bottom."
        )
        return
      }

      config.customMenubar.position = position
    }

    if let heightRaw = menubarTable["height"] {
      guard let height = numberValue(from: heightRaw) else {
        errors.append("custom_menubar.height: Expected number, got \(heightRaw.type)")
        return
      }

      guard (24.0...48.0).contains(height) else {
        errors.append("custom_menubar.height: Out of range. Allowed: 24...48.")
        return
      }

      config.customMenubar.height = height
    }

    if let widgetsRaw = menubarTable["widgets"] {
      guard let widgetValues = widgetsRaw.array else {
        errors.append("custom_menubar.widgets: Expected array, got \(widgetsRaw.type)")
        return
      }

      var widgets: [CustomMenubarWidget] = []

      for (index, value) in widgetValues.enumerated() {
        guard let widgetString = value.string else {
          errors.append(
            "custom_menubar.widgets[\(index)]: Expected string, got \(value.type)"
          )
          continue
        }

        guard let widget = CustomMenubarWidget(rawValue: widgetString) else {
          errors.append(
            "custom_menubar.widgets[\(index)]: Invalid value '\(widgetString)'. Allowed: front_app, clock."
          )
          continue
        }

        widgets.append(widget)
      }

      if !widgets.isEmpty {
        config.customMenubar.widgets = widgets
      }
    }

    if let opacityRaw = menubarTable["background_opacity"] {
      guard let opacity = numberValue(from: opacityRaw) else {
        errors.append(
          "custom_menubar.background_opacity: Expected number, got \(opacityRaw.type)"
        )
        return
      }

      guard (0.1...1.0).contains(opacity) else {
        errors.append(
          "custom_menubar.background_opacity: Out of range. Allowed: 0.1...1.0."
        )
        return
      }

      config.customMenubar.backgroundOpacity = opacity
    }

    if let paddingRaw = menubarTable["horizontal_padding"] {
      guard let padding = numberValue(from: paddingRaw) else {
        errors.append(
          "custom_menubar.horizontal_padding: Expected number, got \(paddingRaw.type)"
        )
        return
      }

      guard (0.0...40.0).contains(padding) else {
        errors.append(
          "custom_menubar.horizontal_padding: Out of range. Allowed: 0...40."
        )
        return
      }

      config.customMenubar.horizontalPadding = padding
    }

    if let clock24hRaw = menubarTable["clock_24h"] {
      guard let clock24h = clock24hRaw.bool else {
        errors.append("custom_menubar.clock_24h: Expected bool, got \(clock24hRaw.type)")
        return
      }

      config.customMenubar.clock24h = clock24h
    }
  }

  private func parseGaps(
    _ raw: TOMLValueConvertible,
    config: inout GizmoConfig,
    errors: inout [String]
  ) {
    guard let gapsTable = raw.table else {
      errors.append("gaps: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: gapsTable,
      allowed: ["inner", "outer"],
      prefix: "gaps",
      errors: &errors
    )

    if let innerRaw = gapsTable["inner"] {
      parseInnerGaps(
        innerRaw,
        innerGaps: &config.gaps.inner,
        errors: &errors
      )
    }

    if let outerRaw = gapsTable["outer"] {
      parseOuterGaps(
        outerRaw,
        outerGaps: &config.gaps.outer,
        errors: &errors
      )
    }
  }

  private func parseInnerGaps(
    _ raw: TOMLValueConvertible,
    innerGaps: inout WindowManagerInnerGaps,
    errors: inout [String]
  ) {
    guard let innerTable = raw.table else {
      errors.append("gaps.inner: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: innerTable,
      allowed: ["horizontal", "vertical"],
      prefix: "gaps.inner",
      errors: &errors
    )

    if let horizontalRaw = innerTable["horizontal"] {
      guard let horizontal = nonNegativeNumberValue(
        from: horizontalRaw,
        path: "gaps.inner.horizontal",
        errors: &errors
      ) else {
        return
      }

      innerGaps.horizontal = horizontal
    }

    if let verticalRaw = innerTable["vertical"] {
      guard let vertical = nonNegativeNumberValue(
        from: verticalRaw,
        path: "gaps.inner.vertical",
        errors: &errors
      ) else {
        return
      }

      innerGaps.vertical = vertical
    }
  }

  private func parseOuterGaps(
    _ raw: TOMLValueConvertible,
    outerGaps: inout WindowManagerOuterGaps,
    errors: inout [String]
  ) {
    guard let outerTable = raw.table else {
      errors.append("gaps.outer: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: outerTable,
      allowed: ["left", "top", "right", "bottom"],
      prefix: "gaps.outer",
      errors: &errors
    )

    if let leftRaw = outerTable["left"] {
      guard let left = nonNegativeNumberValue(
        from: leftRaw,
        path: "gaps.outer.left",
        errors: &errors
      ) else {
        return
      }

      outerGaps.left = left
    }

    if let topRaw = outerTable["top"] {
      guard let top = nonNegativeNumberValue(
        from: topRaw,
        path: "gaps.outer.top",
        errors: &errors
      ) else {
        return
      }

      outerGaps.top = top
    }

    if let rightRaw = outerTable["right"] {
      guard let right = nonNegativeNumberValue(
        from: rightRaw,
        path: "gaps.outer.right",
        errors: &errors
      ) else {
        return
      }

      outerGaps.right = right
    }

    if let bottomRaw = outerTable["bottom"] {
      guard let bottom = nonNegativeNumberValue(
        from: bottomRaw,
        path: "gaps.outer.bottom",
        errors: &errors
      ) else {
        return
      }

      outerGaps.bottom = bottom
    }
  }

  private func parseKeystats(
    _ raw: TOMLValueConvertible,
    config: inout GizmoConfig,
    errors: inout [String]
  ) {
    guard let keystatsTable = raw.table else {
      errors.append("keystats: Expected table, got \(raw.type)")
      return
    }

    appendUnknownKeys(
      in: keystatsTable,
      allowed: ["auto_start_monitoring"],
      prefix: "keystats",
      errors: &errors
    )

    if let autoStartRaw = keystatsTable["auto_start_monitoring"] {
      guard let autoStart = autoStartRaw.bool else {
        errors.append(
          "keystats.auto_start_monitoring: Expected bool, got \(autoStartRaw.type)"
        )
        return
      }

      config.keystats.autoStartMonitoring = autoStart
    }
  }

  private func appendUnknownKeys(
    in table: TOMLTable,
    allowed: Set<String>,
    prefix: String,
    errors: inout [String]
  ) {
    for (key, _) in table where !allowed.contains(key) {
      let path = prefix.isEmpty ? key : "\(prefix).\(key)"
      errors.append("\(path): Unknown key.")
    }
  }

  private func numberValue(from value: TOMLValueConvertible) -> Double? {
    if let double = value.double { return double }
    if let int = value.int { return Double(int) }
    return nil
  }

  private func nonNegativeNumberValue(
    from value: TOMLValueConvertible,
    path: String,
    errors: inout [String]
  ) -> Double? {
    guard let number = numberValue(from: value) else {
      errors.append("\(path): Expected number, got \(value.type)")
      return nil
    }

    guard number >= 0 else {
      errors.append("\(path): Out of range. Allowed: >= 0.")
      return nil
    }

    return number
  }
}
