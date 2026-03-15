import SwiftUI

struct AuthView: View {
    @EnvironmentObject var service: ProjectXService

    @State private var userName  = ""
    @State private var apiKey    = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Credentials") {
                    TextField("Username", text: $userName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
        _ = await service.login(userName: userName, apiKey: apiKey)
        isLoading = false
    }
}
