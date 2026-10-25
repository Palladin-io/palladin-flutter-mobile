import AuthenticationServices

// Compile-only contract for the SDK APIs used by CredentialProvider.
@available(iOS 26.2, *)
final class GeneratedPasswordSDKContract: ASCredentialProviderViewController {
    override func prepareInterface(for request: ASGeneratePasswordsRequest) {
        let password = ASGeneratedPassword(kind: .strong, value: "dummy-test-password")
        extensionContext.completeGeneratePasswordRequest(
            results: [password], completionHandler: nil
        )
    }
}
