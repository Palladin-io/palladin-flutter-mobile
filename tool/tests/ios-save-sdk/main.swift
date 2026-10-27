import AuthenticationServices
import Foundation

if #available(iOS 26.2, *) {
    for event in [ASSavePasswordRequest.Event.userInitiated, .formDidDisappear, .generatedPasswordFilled] {
        for type in [ASCredentialServiceIdentifier.IdentifierType.URL, .domain] {
            for identifier in ["https://login.example.test/path", "login.example.test", "http://login.example.test",
                               "https://user@login.example.test", "https://login.example.test:443"] {
                let request = ASSavePasswordRequest(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: identifier, type: type),
                    credential: ASPasswordCredential(user: "synthetic-user", password: "synthetic-password"),
                    sessionID: "synthetic-form", event: event)
                let expected = event == .userInitiated && type == .URL && identifier == "https://login.example.test/path"
                    ? "https://login.example.test" : nil
                precondition(PendingPasswordSave.origin(for: request) == expected,
                             "Only an explicit exact HTTPS URL request may be staged")
            }
        }
    }
    print("iOS real SDK save request event/type tests passed")
}
