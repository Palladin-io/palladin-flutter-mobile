import Foundation
func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func rejects(_ operation: () throws -> Void) { do { try operation(); fatalError("expected rejection") } catch {} }
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
defer { try? FileManager.default.removeItem(at:directory) }
var durable:Data?
let source = SharedMemberSourceFence(containerURL:directory,readState:{durable},writeState:{durable=$0})
let claims = try SharedMemberSourceClaims(arguments:["principalId":"member","organizationId":"org","organizationMembershipGeneration":"1","offlinePolicy":"1h","offlinePolicyVersion":1])
let snapshot = try source.beginSession(sessionID:"app",profileBinding:String(repeating:"a",count:64),claims:claims,accountUnlock:["accountId":"member","encryptedPrivateKey":"synthetic","kdf":["securityVersion":1,"minimumSecurityVersion":1,"profileId":"identity-argon2id-password-v1","kdfSalt":"synthetic","credentialRevision":1,"privateKeyWrapRevision":1]])
try source.activate(snapshot)
func request(hosts:Set<String> = ["example.invalid"]) throws -> SharedMemberCredentialRequest {
    try SharedMemberCredentialRequest(source:source,snapshot:snapshot,verifiedHosts:hosts)
}
func row(_ id:String) -> [String:Any] { ["selectionId":id+"/0","label":"Synthetic","domains":["example.invalid"]] }
func response(_ owner:SharedMemberCredentialRequest) -> [String:Any] {
    ["requestId":owner.id,"selectionId":owner.id+"/0","selectedHost":"example.invalid","username":"synthetic","password":"synthetic-only","accessContext":["principalId":"member","organizationId":"org","organizationMembershipGeneration":"1","offlinePolicy":"1h","offlinePolicyVersion":1,"notAfter":ISO8601DateFormatter().string(from:Date().addingTimeInterval(600))]]
}
let canceled = try request()
let oldAttempt = try canceled.beginAuthentication()
canceled.cancel()
rejects { try canceled.authenticationSucceeded(oldAttempt,rows:[row(canceled.id)]) }
let first = try request()
rejects { _ = try first.prepareSelection(id:first.id+"/0",host:"example.invalid",manualConfirmed:false) }
let attempt = try first.beginAuthentication()
rejects { try first.authenticationSucceeded(UUID(),rows:[row(first.id)]) }
try first.authenticationSucceeded(attempt,rows:[row(first.id)])
rejects { _ = try first.prepareSelection(id:first.id+"/0",host:"sibling.example.invalid",manualConfirmed:false) }
_ = try first.prepareSelection(id:first.id+"/0",host:"example.invalid",manualConfirmed:false)
var sent = 0
try first.complete(response(first)) { user,password in expect(user=="synthetic" && password=="synthetic-only","selected values"); sent+=1 }
expect(sent==1,"handoff once")
rejects { try first.complete(response(first)) { _,_ in sent+=1 } }
let manual = try request(hosts:[])
try manual.authenticationSucceeded(manual.beginAuthentication(),rows:[row(manual.id)])
rejects { _ = try manual.prepareSelection(id:manual.id+"/0",host:"example.invalid",manualConfirmed:false) }
_ = try manual.prepareSelection(id:manual.id+"/0",host:"example.invalid",manualConfirmed:true)
var wrong = response(manual)
var context = wrong["accessContext"] as! [String:Any]
context["principalId"]="other"; wrong["accessContext"]=context
rejects { try manual.complete(wrong) { _,_ in fatalError("wrong account") } }
let expired = try request()
try expired.authenticationSucceeded(expired.beginAuthentication(),rows:[row(expired.id)])
_ = try expired.prepareSelection(id:expired.id+"/0",host:"example.invalid",manualConfirmed:false)
var stale = response(expired)
context = stale["accessContext"] as! [String:Any]
context["notAfter"] = ISO8601DateFormatter().string(from:Date().addingTimeInterval(-1));stale["accessContext"]=context
rejects { try expired.complete(stale) { _,_ in fatalError("expired lease") } }
let revoked = try request()
try revoked.authenticationSucceeded(revoked.beginAuthentication(),rows:[row(revoked.id)])
_ = try revoked.prepareSelection(id:revoked.id+"/0",host:"example.invalid",manualConfirmed:false)
_ = try source.invalidate(snapshot)
rejects { try revoked.complete(response(revoked)) { _,_ in fatalError("revoked source") } }
print("PASS request-owned authentication, cancellation, exact destination, manual consent, expiry and revocation")
