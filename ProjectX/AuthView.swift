import SwiftUI

struct AuthView: View {
    @Environment(ProjectXService.self) var service

    @State private var userName  = ""
    @State private var apiKey    = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Credentials") {
                    TextField("Username", text: $userName)
                        .autocorrectionDisabled()
                        #if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("API Key", text: $apiKey)
                }
                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView() }
                            else { Text("Sign In").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(userName.isEmpty || apiKey.isEmpty || isLoading)
                }
                if let err = service.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("ProjectX Login")
        }
        .onAppear {
            userName = service.savedUsername ?? ""
            apiKey   = service.savedApiKey   ?? ""
        }
    }

    private func login() async {
        isLoading = true
        let ok = await service.login(userName: userName, apiKey: apiKey)
        if ok { await service.fetchAccounts() }
        isLoading = false
    }
}
