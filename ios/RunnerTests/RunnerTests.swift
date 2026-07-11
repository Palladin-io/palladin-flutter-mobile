import AuthenticationServices
import XCTest
@testable import PalladinAutoFillBridge

final class RunnerTests: XCTestCase {
    func testAutoFillDomainNormalization() {
        XCTAssertEqual(
            AutoFillCredentialRecord.normalizeDomain("https://WWW.Example.com/login"),
            "example.com"
        )
        XCTAssertNil(AutoFillCredentialRecord.normalizeDomain("localhost"))
        XCTAssertNil(AutoFillCredentialRecord.normalizeDomain("example..com"))
    }

    func testAutoFillMatchesExactDomainOnly() {
        let record = AutoFillCredentialRecord(
            id: "entry-1",
            label: "Example",
            username: "user@example.com",
            password: "test-only-password",
            domains: ["example.com"]
        )

        XCTAssertTrue(record.matches(serviceIdentifiers: [
            ASCredentialServiceIdentifier(identifier: "example.com", type: .domain),
        ]))
        XCTAssertFalse(record.matches(serviceIdentifiers: [
            ASCredentialServiceIdentifier(identifier: "login.example.com", type: .domain),
        ]))
    }
}
