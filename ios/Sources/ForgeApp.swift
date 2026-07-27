import SwiftUI

@main
struct ForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Forge design tokens — the family neutrals with the ember accent.
enum FG {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.047) // #0f0d0c
    static let card = Color(red: 0.102, green: 0.094, blue: 0.086)       // #1a1816
    static let secondary = Color(red: 0.153, green: 0.145, blue: 0.137)  // #272523
    static let border = Color.white.opacity(0.16)
    static let muted = Color(red: 0.682, green: 0.667, blue: 0.647)      // #aeaaa5
    static let ember = Color(red: 0.871, green: 0.518, blue: 0.310)      // #de844f
    static let emberSoft = Color(red: 0.871, green: 0.518, blue: 0.310).opacity(0.16)
    static let gold = Color(red: 0.765, green: 0.604, blue: 0.333)       // #c39a55
    static let success = Color(red: 0.435, green: 0.718, blue: 0.537)
}

struct RootView: View {
    @AppStorage("forge_base_url") private var baseURL = ""
    @AppStorage("forge_token") private var token = ""

    var body: some View {
        if baseURL.isEmpty || token.isEmpty {
            PairingView()
        } else {
            HomeView()
        }
    }
}
