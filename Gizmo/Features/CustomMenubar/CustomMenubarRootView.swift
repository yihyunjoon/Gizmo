import SwiftUI

struct CustomMenubarRootView: View {
  @Bindable var model: CustomMenubarModel
  let onWorkspaceTap: (String) -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(model.config.backgroundOpacity)

      HStack(spacing: 10) {
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
          .overlay(Color.white.opacity(0.18))
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
    HStack(spacing: 6) {
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

    return HStack(spacing: 5) {
      Text(workspaceName.uppercased())
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(isFocused ? Color.white.opacity(0.96) : Color.white.opacity(0.74))

      if !appNames.isEmpty {
        Text("|")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(isFocused ? Color.white.opacity(0.7) : Color.white.opacity(0.48))

        Text(appNames.joined(separator: " · "))
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(isFocused ? Color.white.opacity(0.86) : Color.white.opacity(0.62))
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .padding(.horizontal, 7)
    .frame(height: 24)
    .background(
      Capsule(style: .continuous)
        .fill(isFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.12))
    )
  }

  func customWidgets(alignedTo alignment: CustomWidgetAlignment) -> some View {
    HStack(spacing: 10) {
      ForEach(model.widgetNames(alignedTo: alignment), id: \.self) { widgetName in
        customWidgetView(named: widgetName)
      }
    }
  }

  func customWidgetView(named widgetName: String) -> some View {
    Text(model.customWidgetText(named: widgetName))
      .font(.system(size: 11, weight: .semibold, design: .monospaced))
      .foregroundStyle(.white.opacity(0.96))
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
