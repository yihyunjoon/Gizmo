import SwiftUI

struct GizmoTheme {
  static let current = GizmoTheme()

  let customMenubar = CustomMenubar()
  let launcher = Launcher()

  struct Launcher {
    let maxVisibleRows = 5
    let maxVisibleRowsWhenError = 3
    let rowHeight: CGFloat = 33
    let rowSpacing: CGFloat = 6
    let listVerticalPadding: CGFloat = 2
    let leadingSlotSize: CGFloat = 18
    let iconCornerRadius: CGFloat = 4
    let rowContentSpacing: CGFloat = 8
    let contentSpacing: CGFloat = 12
    let searchFieldSpacing: CGFloat = 10
    let errorContentSpacing: CGFloat = 8
    let panelPadding: CGFloat = 16
    let panelWidth: CGFloat = 640
    let panelCornerRadius: CGFloat = 16
    let panelOuterPadding: CGFloat = 12
    let panelBorderColor = Color.white.opacity(0.18)
    let panelBorderWidth: CGFloat = 1
    let rowHorizontalPadding: CGFloat = 10
    let rowVerticalPadding: CGFloat = 8
    let rowCornerRadius: CGFloat = 8

    let searchIconFont = Font.system(size: 18, weight: .medium)
    let searchInputFont = Font.system(size: 24, weight: .medium, design: .rounded)
    let emptyResultFont = Font.system(size: 13, weight: .regular, design: .rounded)
    let commandTitleFont = Font.system(size: 14, weight: .medium, design: .rounded)

    func rowBackgroundColor(isSelected: Bool) -> Color {
      isSelected ? Color.blue.opacity(0.22) : Color.clear
    }
  }

  struct CustomMenubar {
    let backgroundColor = Color.black
    let contentSpacing: CGFloat = 10
    let workspaceStripSpacing: CGFloat = 6
    let workspaceButtonContentSpacing: CGFloat = 5
    let workspaceButtonHorizontalPadding: CGFloat = 7
    let workspaceButtonHeight: CGFloat = 24
    let workspaceDetailsSeparator = "|"
    let workspaceAppNameSeparator = " · "
    let borderColor = Color.white.opacity(0.18)

    let workspaceNameFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    let workspaceDetailsSeparatorFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    let workspaceAppNameFont = Font.system(size: 11, weight: .medium, design: .rounded)
    let customWidgetFont = Font.system(size: 11, weight: .semibold, design: .monospaced)

    let customWidgetTextColor = Color.white.opacity(0.96)

    func workspaceNameColor(isFocused: Bool) -> Color {
      Color.white.opacity(isFocused ? 0.96 : 0.74)
    }

    func workspaceDetailsSeparatorColor(isFocused: Bool) -> Color {
      Color.white.opacity(isFocused ? 0.7 : 0.48)
    }

    func workspaceAppNameColor(isFocused: Bool) -> Color {
      Color.white.opacity(isFocused ? 0.86 : 0.62)
    }

    func workspaceButtonBackgroundColor(isFocused: Bool) -> Color {
      Color.white.opacity(isFocused ? 0.24 : 0.12)
    }
  }
}
