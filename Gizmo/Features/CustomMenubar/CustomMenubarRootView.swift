import SwiftUI

struct CustomMenubarRootView: View {
  @Bindable var model: CustomMenubarModel
  let items: [CustomMenubarItem]

  var body: some View {
    ZStack {
      Color.black.opacity(model.config.backgroundOpacity)

      HStack(spacing: 10) {
        HStack(spacing: 6) {
          ForEach(items) { item in
            Button {
              item.action()
            } label: {
              Label(item.title, systemImage: item.systemImage)
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(Color.white.opacity(0.18))
          }
        }

        Spacer(minLength: 0)

        if model.hasWidget(.frontApp) {
          Text(model.frontAppName)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
        }

        Spacer(minLength: 0)

        if model.hasWidget(.clock) {
          Text(model.clockText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.96))
            .lineLimit(1)
        }
      }
      .padding(.horizontal, CGFloat(model.config.horizontalPadding))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
