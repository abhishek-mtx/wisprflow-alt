import SwiftUI

@main
struct CompareLabApp: App {
    @State private var session = CompareSession()

    var body: some Scene {
        Window("Compare", id: "compare") {
            CompareRootView()
                .environment(session)
                .frame(minWidth: 980, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 620)
        .windowResizability(.contentSize)
    }
}
