import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            DictionaryView()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            StylesView()
                .tabItem { Label("Styles", systemImage: "paintbrush") }
            SnippetsView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            TransformsView()
                .tabItem { Label("Transforms", systemImage: "arrow.2.squarepath") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            InjectionProfilesView()
                .tabItem { Label("Injection", systemImage: "arrow.right.doc.on.clipboard") }
        }
        .padding(.top, 8)
    }
}
