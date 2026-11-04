import Foundation
func expect(_ value:@autoclosure()->Bool,_ message:String) { if !value(){fatalError(message)} }
func rejects(_ operation:()throws->Void){do{try operation();fatalError("expected rejection")}catch{}}
let container=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let directory=container.appendingPathComponent("member-source")
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:container)}
let staged=directory.appendingPathComponent("vault_member_sync.db.migrating")
let target=directory.appendingPathComponent("vault_member_sync.db")
rejects{try commitMemberSourceMigration(in:container)}
try Data("synthetic-encrypted-snapshot".utf8).write(to:staged)
try commitMemberSourceMigration(in:container)
expect(!FileManager.default.fileExists(atPath:staged.path),"atomic rename consumes staging file")
let original=try Data(contentsOf:target)
try Data("must-not-overwrite".utf8).write(to:staged)
rejects{try commitMemberSourceMigration(in:container)}
let unchanged=try Data(contentsOf:target)
expect(unchanged==original,"existing canonical DB must remain unchanged")
try FileManager.default.removeItem(at:staged)
try FileManager.default.removeItem(at:target)
let outside=container.appendingPathComponent("outside")
try Data("synthetic-outside".utf8).write(to:outside)
try FileManager.default.createSymbolicLink(at:staged,withDestinationURL:outside)
rejects{try commitMemberSourceMigration(in:container)}
expect(!FileManager.default.fileExists(atPath:target.path),"symlink staging must not become canonical")
try FileManager.default.removeItem(at:staged)
try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:false)
rejects{try commitMemberSourceMigration(in:container)}
print("PASS durable fixed-path migration, absent-target CAS and invalid-file negatives")
