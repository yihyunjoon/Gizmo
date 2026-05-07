import SwiftUI

struct CustomMenubarRootView: View {
  @Bindable var model: CustomMenubarModel
  let onWorkspaceTap: (String) -> Void
  private let theme = GizmoTheme.current

  var body: some View {
    ZStack {
      theme.customMenubar.backgroundColor.opacity(model.config.backgroundOpacity)

      HStack(spacing: theme.customMenubar.contentSpacing) {
        workspaceStrip
        customWidgets(alignedTo: .left)
        Spacer(minLength: 0)
        customWidgets(alignedTo: .right)
      }
      .padding(.horizontal, CGFloat(model.config.horizontalPadding))
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      customWidgets(alignedTo: .center)
        .padding(.horizontal, CGFloat(model.config.horizontalPadding))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
    .frame(height: CGFloat(model.config.height))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: model.config.position.borderAlignment) {
      if model.config.border {
        Divider()
          .overlay(theme.customMenubar.borderColor)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      // Intentionally capture background clicks to keep full-width interaction behavior.
    }
  }
}

private extension CustomMenubarRootView {
  var workspaceStrip: some View {
    HStack(spacing: theme.customMenubar.workspaceStripSpacing) {
      ForEach(model.workspaceNames, id: \.self) { workspaceName in
        Button {
          onWorkspaceTap(workspaceName)
        } label: {
          workspaceButtonLabel(for: workspaceName)
        }
        .buttonStyle(.plain)
      }
    }
  }

  func workspaceButtonLabel(for workspaceName: String) -> some View {
    let appNames = model.appNames(for: workspaceName)
    let isFocused = model.isFocusedWorkspace(workspaceName)

    return HStack(spacing: theme.customMenubar.workspaceButtonContentSpacing) {
      Text(workspaceName.uppercased())
        .font(theme.customMenubar.workspaceNameFont)
        .foregroundStyle(theme.customMenubar.workspaceNameColor(isFocused: isFocused))

      if !appNames.isEmpty {
        Text(theme.customMenubar.workspaceDetailsSeparator)
          .font(theme.customMenubar.workspaceDetailsSeparatorFont)
          .foregroundStyle(theme.customMenubar.workspaceDetailsSeparatorColor(isFocused: isFocused))

        Text(appNames.joined(separator: theme.customMenubar.workspaceAppNameSeparator))
          .font(theme.customMenubar.workspaceAppNameFont)
          .foregroundStyle(theme.customMenubar.workspaceAppNameColor(isFocused: isFocused))
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .padding(.horizontal, theme.customMenubar.workspaceButtonHorizontalPadding)
    .frame(height: theme.customMenubar.workspaceButtonHeight)
    .background(
      Capsule(style: .continuous)
        .fill(theme.customMenubar.workspaceButtonBackgroundColor(isFocused: isFocused))
    )
  }

  func customWidgets(alignedTo alignment: CustomWidgetAlignment) -> some View {
    HStack(spacing: theme.customMenubar.contentSpacing) {
      ForEach(model.widgetNames(alignedTo: alignment), id: \.self) { widgetName in
        customWidgetView(named: widgetName)
      }
    }
  }

  func customWidgetView(named widgetName: String) -> some View {
    Text(model.customWidgetText(named: widgetName))
      .font(theme.customMenubar.customWidgetFont)
      .foregroundStyle(theme.customMenubar.customWidgetTextColor)
      .lineLimit(1)
      .truncationMode(.tail)
  }
}

private extension CustomMenubarPosition {
  var borderAlignment: Alignment {
    switch self {
    case .top:
      return .bottom
    case .bottom:
      return .top
    }
  }
}
