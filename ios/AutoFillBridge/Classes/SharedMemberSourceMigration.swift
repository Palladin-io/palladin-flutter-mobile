import Darwin
import Foundation

/// Commits only the app's fixed encrypted SQLite staging file. A successful
/// return is the durability acknowledgement; the legacy DB is still Dart-owned.
func commitMemberSourceMigration(in containerURL: URL) throws {
    let directoryURL = containerURL.appendingPathComponent("member-source", isDirectory: true)
    let directory = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard directory >= 0 else { throw SharedMemberSourceError.unavailable }
    defer { close(directory) }
    let stagedName = "vault_member_sync.db.migrating"
    let targetName = "vault_member_sync.db"
    let staged = openat(directory, stagedName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard staged >= 0 else { throw SharedMemberSourceError.unavailable }
    defer { close(staged) }
    var information = stat()
    guard fstat(staged, &information) == 0,
          information.st_mode & S_IFMT == S_IFREG, information.st_nlink == 1,
          fsync(staged) == 0 else { throw SharedMemberSourceError.unavailable }
    // RENAME_EXCL is the atomic absent-target check; a preflight exists() check
    // cannot provide this boundary against a concurrent migration or startup.
    guard renameatx_np(directory, stagedName, directory, targetName, UInt32(RENAME_EXCL)) == 0,
          fsync(directory) == 0 else { throw SharedMemberSourceError.unavailable }
}
