import SwiftUI

struct GizmoSplitView: View {
  @State private var selectedItem: NavigationItem? = .general

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedItem) {
        ForEach(NavigationItem.primaryItems) { item in
          Label(
            String(localized: item.name),
            systemImage: item.symbolName
          )
          .tag(item)
        }

        ForEach(NavigationItem.sidebarSections) { section in
          Section {
            ForEach(section.items) { item in
              Label(
                String(localized: item.name),
                systemImage: item.symbolName
              )
              .tag(item)
            }
          } header: {
            Text(String(localized: section.title))
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 250)
    } detail: {
      if let selectedItem {
        selectedItem.viewForPage()
      } else {
        Text(String(localized: "Select an item"))
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview {
  GizmoSplitView()
}
