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
          Text(workspaceName)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(
              model.isFocusedWorkspace(workspaceName)
                ? Color.white.opacity(0.96)
                : Color.white.opacity(0.74)
            )
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
              Capsule(style: .continuous)
                .fill(
                  model.isFocusedWorkspace(workspaceName)
                    ? Color.white.opacity(0.24)
                    : Color.white.opacity(0.12)
                )
            )
        }
        .buttonStyle(.plain)
      }
    }
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
