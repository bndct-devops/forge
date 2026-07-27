import SwiftUI

struct PairingView: View {
    @AppStorage("forge_base_url") private var storedURL = ""
    @AppStorage("forge_paired") private var storedPaired = false
    @State private var url = "https://forge.bndct.dev"
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                RoundedRectangle(cornerRadius: 14)
                    .fill(FG.ember)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.black.opacity(0.8))
                    )
                Text("Pair with Forge")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                Text("your instance URL and a full-scope API token\n(Settings → API in Forge)")
                    .font(.system(size: 13))
                    .foregroundStyle(FG.muted)
                    .multilineTextAlignment(.center)

                VStack(spacing: 0) {
                    TextField("https://forge.example.com", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(14)
                    Rectangle().fill(FG.border).frame(height: 1)
                    SecureField("forge_pat_…", text: $token)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(14)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                .foregroundStyle(.white)

                if let error {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }

                Button {
                    Task { await pair() }
                } label: {
                    Text(busy ? "checking…" : "Connect")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(FG.ember))
                        .foregroundStyle(.black.opacity(0.8))
                        .opacity(busy || token.isEmpty ? 0.35 : 1)
                }
                .disabled(busy || token.isEmpty)
                .animation(.easeOut(duration: 0.15), value: token.isEmpty)
                Spacer()
                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private func pair() async {
        busy = true
        error = nil
        let previousURL = UserDefaults.standard.string(forKey: "forge_base_url") ?? ""
        let previousToken = Keychain.get("forge_token")
        UserDefaults.standard.set(url, forKey: "forge_base_url")
        Keychain.set(token, key: "forge_token")
        do {
            try await ForgeAPI.ping()
            storedURL = url
            storedPaired = true
        } catch {
            self.error = error.localizedDescription
            UserDefaults.standard.set(previousURL, forKey: "forge_base_url")
            if let previousToken {
                Keychain.set(previousToken, key: "forge_token")
            } else {
                Keychain.delete("forge_token")
            }
        }
        busy = false
    }
}
