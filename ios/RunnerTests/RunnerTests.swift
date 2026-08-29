import AuthenticationServices
import CryptoKit
import XCTest
@testable import PalladinAutoFillBridge

final class RunnerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_004_800) // 2026-08-29T00:00:00Z

    func testAutoFillDomainNormalization() {
        XCTAssertEqual(
            AutoFillCredentialRecord.normalizeDomain("https://WWW.Example.com/login"),
            "www.example.com"
        )
        XCTAssertNil(AutoFillCredentialRecord.normalizeDomain("localhost"))
        XCTAssertNil(AutoFillCredentialRecord.normalizeDomain("example..com"))
        XCTAssertNotEqual(
            AutoFillCredentialRecord.normalizeDomain("www.example.com"),
            AutoFillCredentialRecord.normalizeDomain("example.com")
        )
    }

    func testAutoFillMatchesExactDomainOnly() {
        let record = AutoFillCredentialRecord(
            id: "entry-1",
            organizationId: "org-1",
            vaultId: "vault-1",
            revision: "41",
            keyVersion: 7,
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

    func testV2PayloadAcceptsCompleteIndependentAuthority() throws {
        let payload = try AutoFillPayloadValidator.validate(fixturePayload(), now: now)

        XCTAssertEqual(payload.records.count, 1)
        XCTAssertEqual(payload.records.first?.revision, "41")
        XCTAssertEqual(payload.records.first?.keyVersion, 7)
        XCTAssertEqual(payload.manifest.principalId, "principal-1")
        XCTAssertEqual(payload.manifest.organizationId, "org-1")
    }

    func testV2PayloadRejectsRecordSubstitutionAgainstUnchangedManifest() {
        var payload = fixturePayload()
        payload["records"] = mutatedFirstRecord(payload) { record in
            record["vaultId"] = "vault-substituted"
        }

        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(payload, now: now))
    }

    func testV2PayloadRejectsStaleRevisionAndKeyVersion() {
        var staleRevision = fixturePayload()
        staleRevision["records"] = mutatedFirstRecord(staleRevision) { record in
            record["revision"] = "40"
        }
        var staleKey = fixturePayload()
        staleKey["records"] = mutatedFirstRecord(staleKey) { record in
            record["keyVersion"] = 6
        }

        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(staleRevision, now: now))
        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(staleKey, now: now))
    }

    func testV2PayloadRejectsNonCanonicalDecimalAuthorityAndRecordRevision() {
        var payload = fixturePayload()
        payload["manifest"] = mutatedFirstVault(payload) { vault in
            guard var entries = vault["entries"] as? [[String: Any]], !entries.isEmpty else {
                return XCTFail("Invalid entry fixture")
            }
            entries[0]["revision"] = "041"
            vault["entries"] = entries
        }
        payload["records"] = mutatedFirstRecord(payload) { record in
            record["revision"] = "041"
        }

        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(payload, now: now))
    }

    func testV2PayloadRejectsChangedAccessContextAndExpiredLease() {
        var changedContext = fixturePayload()
        changedContext["manifest"] = mutatedFirstVault(changedContext) { vault in
            vault["memberId"] = "other-principal"
        }
        var expired = fixturePayload()
        expired["manifest"] = mutatedFirstVault(expired) { vault in
            vault["issuedAt"] = "2026-08-27T00:00:00.000Z"
            vault["notAfter"] = "2026-08-28T00:00:00.000Z"
        }

        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(changedContext, now: now))
        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(expired, now: now))
    }

    func testLegacyV1PayloadIsRejected() {
        var payload = fixturePayload()
        payload["version"] = 1

        XCTAssertThrowsError(try AutoFillPayloadValidator.validate(payload, now: now)) { error in
            guard case AutoFillCacheError.unsupportedVersion = error else {
                return XCTFail("Expected unsupportedVersion")
            }
        }
    }

    func testMaximumObservedWallTimeRejectsRollbackBeyondFiveMinutes() throws {
        let maximum = Date(timeIntervalSince1970: 20_000)

        XCTAssertEqual(
            try AutoFillWallTimeGuard.maximumObservedWallTime(
                now: maximum.addingTimeInterval(-300),
                previous: maximum
            ),
            maximum
        )
        XCTAssertThrowsError(
            try AutoFillWallTimeGuard.maximumObservedWallTime(
                now: maximum.addingTimeInterval(-301),
                previous: maximum
            )
        ) { error in
            guard case AutoFillCacheError.clockRollback = error else {
                return XCTFail("Expected clockRollback")
            }
        }
    }

    func testMaximumObservedWallTimeStateIsAuthenticatedAndGenerationBound() throws {
        let key = Data(repeating: 0xA5, count: 32)
        let maximum = Date(timeIntervalSince1970: 20_000)
        let sealed = try AutoFillWallTimeStateCodec.seal(
            maximumObserved: maximum,
            generation: 12,
            cacheId: "cache-current",
            keyBytes: key
        )

        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains("20000000"))
        XCTAssertEqual(
            try AutoFillWallTimeStateCodec.open(
                sealed,
                generation: 12,
                cacheId: "cache-current",
                keyBytes: key
            ),
            maximum
        )
        XCTAssertThrowsError(try AutoFillWallTimeStateCodec.open(
            sealed,
            generation: 13,
            cacheId: "cache-current",
            keyBytes: key
        ))
        XCTAssertThrowsError(try AutoFillWallTimeStateCodec.open(
            sealed,
            generation: 12,
            cacheId: "cache-substituted",
            keyBytes: key
        ))
    }

    func testGlobalMaximumObservedWallTimeSurvivesGenerationRotation() throws {
        let initial = Date(timeIntervalSince1970: 20_000)
        let forward = try AutoFillWallTimeCoordinator.maximumObservedWallTime(
            now: initial.addingTimeInterval(20 * 60 * 60),
            globalPrevious: initial,
            generationPrevious: initial
        )

        XCTAssertThrowsError(try AutoFillWallTimeCoordinator.maximumObservedWallTime(
            now: initial.addingTimeInterval(60 * 60),
            globalPrevious: forward,
            generationPrevious: nil
        )) { error in
            guard case AutoFillCacheError.clockRollback = error else {
                return XCTFail("Expected clockRollback after generation rotation")
            }
        }
    }

    func testMonotonicWallTimeRejectsFrozenAndSlowWallClock() throws {
        let frozenGuard = AutoFillMonotonicWallTimeGuard()
        try frozenGuard.validate(wallTime: now, uptime: 1_000)
        XCTAssertThrowsError(try frozenGuard.validate(
            wallTime: now,
            uptime: 1_301
        )) { error in
            guard case AutoFillCacheError.clockRollback = error else {
                return XCTFail("Expected frozen wall clock rejection")
            }
        }

        let slowGuard = AutoFillMonotonicWallTimeGuard()
        try slowGuard.validate(wallTime: now, uptime: 2_000)
        XCTAssertThrowsError(try slowGuard.validate(
            wallTime: now.addingTimeInterval(50),
            uptime: 2_360
        )) { error in
            guard case AutoFillCacheError.clockRollback = error else {
                return XCTFail("Expected slow wall clock rejection")
            }
        }
    }

    func testGlobalWallTimeAuthorityPartialDeletionFailsClosed() throws {
        XCTAssertNoThrow(try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: false,
            globalStateExists: false,
            allowInitialization: true
        ))
        XCTAssertNoThrow(try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: true,
            globalStateExists: true,
            allowInitialization: false
        ))
        XCTAssertThrowsError(try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: true,
            globalStateExists: false,
            allowInitialization: true
        ))
        XCTAssertThrowsError(try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: false,
            globalStateExists: true,
            allowInitialization: true
        ))
        XCTAssertThrowsError(try AutoFillWallTimeAuthorityRules.validatePresence(
            integrityKeyExists: false,
            globalStateExists: false,
            allowInitialization: false
        ))
    }

    func testBeginRollbackQuarantinesCurrentActiveFence() {
        let active = AutoFillFence(generation: 14, state: .active, cacheId: "cache-current")

        XCTAssertEqual(
            AutoFillFenceRules.quarantineAfterAuthorityFailure(
                counter: 14,
                fence: active
            ),
            AutoFillFence(generation: 14, state: .quarantined, cacheId: nil)
        )
        XCTAssertNil(AutoFillFenceRules.quarantineAfterAuthorityFailure(
            counter: 15,
            fence: active
        ))
    }

    func testMissingCorruptAndLateGenerationFenceFailClosed() {
        let active = AutoFillFence(generation: 14, state: .active, cacheId: "cache-current")

        XCTAssertFalse(AutoFillIdentityPublicationGuard.shouldPublish(
            expectedGeneration: 14,
            expectedCacheId: "cache-current",
            currentCounter: nil,
            currentFence: active
        ))
        XCTAssertFalse(AutoFillIdentityPublicationGuard.shouldPublish(
            expectedGeneration: 14,
            expectedCacheId: "cache-current",
            currentCounter: 14,
            currentFence: nil
        ))
        XCTAssertFalse(AutoFillIdentityPublicationGuard.shouldPublish(
            expectedGeneration: 13,
            expectedCacheId: "cache-old",
            currentCounter: 14,
            currentFence: active
        ))
        XCTAssertTrue(AutoFillIdentityPublicationGuard.shouldPublish(
            expectedGeneration: 14,
            expectedCacheId: "cache-current",
            currentCounter: 14,
            currentFence: active
        ))
    }

    func testLateRevokedGenerationCannotDeleteNewGenerationArtifacts() {
        XCTAssertTrue(AutoFillFenceRules.mayDeleteArtifacts(
            artifactGeneration: 20,
            cleanupGeneration: 21,
            currentCounter: 22
        ))
        XCTAssertFalse(AutoFillFenceRules.mayDeleteArtifacts(
            artifactGeneration: 22,
            cleanupGeneration: 21,
            currentCounter: 22
        ))
    }

    func testRevokedFenceCannotBeClearedBackToActive() {
        let revoked = AutoFillFence(generation: 21, state: .revoked, cacheId: nil)
        let active = AutoFillFence(generation: 20, state: .active, cacheId: "cache-old")

        XCTAssertFalse(AutoFillFenceRules.mayClearSession(
            counter: 21,
            fence: revoked,
            sessionToken: 21
        ))
        XCTAssertTrue(AutoFillFenceRules.mayClearSession(
            counter: 20,
            fence: active,
            sessionToken: 20
        ))
        XCTAssertTrue(AutoFillFenceRules.mayDeleteArtifacts(
            artifactGeneration: 20,
            cleanupGeneration: 21,
            currentCounter: 21
        ))
    }

    func testCredentialUseFailsAtExactExpiryAndAfterRevoke() throws {
        let service = ASCredentialServiceIdentifier(identifier: "login.example.com", type: .domain)
        let credential = AutoFillCredentialLease(
            record: AutoFillCredentialRecord(
                id: "entry-1",
                organizationId: "org-1",
                vaultId: "vault-1",
                revision: "41",
                keyVersion: 7,
                label: "Example",
                username: "user@example.com",
                password: "test-only-password",
                domains: ["login.example.com"]
            ),
            notAfter: now,
            generation: 20,
            cacheId: "cache-current",
            maximumObservedWallTime: now.addingTimeInterval(-60)
        )
        let active = AutoFillFence(generation: 20, state: .active, cacheId: "cache-current")

        try AutoFillCredentialUseGuard.validate(
            credential,
            serviceIdentifiers: [service],
            now: now.addingTimeInterval(-1),
            currentCounter: 20,
            currentFence: active
        )
        XCTAssertThrowsError(try AutoFillCredentialUseGuard.validate(
            credential,
            serviceIdentifiers: [service],
            now: now,
            currentCounter: 20,
            currentFence: active
        ))
        XCTAssertThrowsError(try AutoFillCredentialUseGuard.validate(
            credential,
            serviceIdentifiers: [service],
            now: now.addingTimeInterval(-1),
            currentCounter: 21,
            currentFence: AutoFillFence(generation: 21, state: .revoked, cacheId: nil)
        ))
    }

    func testLateIdentitySuccessAfterTimeoutRequiresCompensatingClear() {
        let timedOut = AutoFillAsyncMutationState()
        var releaseCount = 0
        XCTAssertEqual(timedOut.timeoutAction(
            releasingSerializationResources: { releaseCount += 1 }
        ), .returnTimeout)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(timedOut.callbackAction(
            succeeded: true,
            error: nil,
            expectedArtifactIsActive: true
        ), .compensate)
        XCTAssertFalse(AutoFillIdentityCompensationGuard.shouldClearLateReplacement(
            expectedGeneration: 20,
            expectedCacheId: "cache-old",
            currentCounter: 21,
            currentFence: AutoFillFence(
                generation: 21,
                state: .active,
                cacheId: "cache-current"
            )
        ))

        let callbackWon = AutoFillAsyncMutationState()
        XCTAssertEqual(callbackWon.callbackAction(
            succeeded: true,
            error: nil,
            expectedArtifactIsActive: true
        ), .finish)
        XCTAssertEqual(callbackWon.timeoutAction(
            releasingSerializationResources: {
                XCTFail("Completed callback must not use the timeout release path")
            }
        ), .awaitCompletion)

        let revoked = AutoFillAsyncMutationState()
        XCTAssertEqual(revoked.callbackAction(
            succeeded: true,
            error: nil,
            expectedArtifactIsActive: false
        ), .compensate)
    }

    func testBridgeMutationSubmissionsPreserveCallOrder() {
        let queue = AutoFillBridgeMutationQueue()
        let completed = expectation(description: "mutations")
        completed.expectedFulfillmentCount = 2
        let lock = NSLock()
        var order: [Int] = []

        queue.submit {
            lock.lock()
            order.append(1)
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
            lock.lock()
            order.append(2)
            lock.unlock()
            completed.fulfill()
        }
        queue.submit {
            lock.lock()
            order.append(3)
            lock.unlock()
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(order, [1, 2, 3])
    }

    private func fixturePayload() -> [String: Any] {
        [
            "version": 2,
            "manifest": [
                "principalId": "principal-1",
                "organizationId": "org-1",
                "organizationMembershipGeneration": "9",
                "offlinePolicy": "24h",
                "offlinePolicyVersion": 3,
                "vaults": [[
                    "vaultId": "vault-1",
                    "contextVersion": 1,
                    "memberId": "principal-1",
                    "memberKeyGeneration": 4,
                    "vaultKeyVersion": 6,
                    "memberRecipientKeyVersion": 5,
                    "memberRecipientKeyFingerprint": "fixture-fingerprint",
                    "issuedAt": "2026-08-29T00:00:00.000Z",
                    "notAfter": "2026-08-30T00:00:00.000Z",
                    "entries": [[
                        "entryId": "entry-1",
                        "revision": "41",
                        "keyVersion": 7,
                    ]],
                ]],
            ],
            "records": [[
                "id": "entry-1",
                "organizationId": "org-1",
                "vaultId": "vault-1",
                "revision": "41",
                "keyVersion": 7,
                "label": "Canonical login",
                "username": "alice@example.com",
                "password": "test-only-password",
                "domains": ["login.example.com"],
            ]],
        ]
    }

    private func mutatedFirstRecord(
        _ payload: [String: Any],
        mutation: (inout [String: Any]) -> Void
    ) -> [[String: Any]] {
        guard var records = payload["records"] as? [[String: Any]], !records.isEmpty else {
            XCTFail("Invalid record fixture")
            return []
        }
        mutation(&records[0])
        return records
    }

    private func mutatedFirstVault(
        _ payload: [String: Any],
        mutation: (inout [String: Any]) -> Void
    ) -> [String: Any] {
        guard var manifest = payload["manifest"] as? [String: Any],
              var vaults = manifest["vaults"] as? [[String: Any]],
              !vaults.isEmpty else {
            XCTFail("Invalid manifest fixture")
            return [:]
        }
        mutation(&vaults[0])
        manifest["vaults"] = vaults
        return manifest
    }
}
