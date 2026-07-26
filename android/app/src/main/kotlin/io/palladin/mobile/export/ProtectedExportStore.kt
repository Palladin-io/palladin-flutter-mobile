package io.palladin.mobile.export

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/** App-private, short-lived plaintext export staging. */
class ProtectedExportStore(context: Context) {
    private val root = File(context.cacheDir, DIRECTORY_NAME)
    private val open = mutableMapOf<String, OpenExport>()

    init {
        ensureRoot()
    }

    fun create(extension: String): String {
        require(EXTENSION.matches(extension)) { "Invalid extension" }
        ensureRoot()
        val destination = File(root, "${UUID.randomUUID()}.$extension")
        require(destination.parentFile?.canonicalFile == root.canonicalFile)
        check(destination.createNewFile())
        restrictToOwner(destination)
        val id = destination.nameWithoutExtension
        open[id] = OpenExport(destination, FileOutputStream(destination, true))
        return id
    }

    fun append(id: String, bytes: ByteArray) {
        require(bytes.size <= MAX_CHUNK_BYTES) { "Chunk too large" }
        val export = open[id] ?: throw IllegalArgumentException("Unknown export")
        require(export.bytes + bytes.size.toLong() <= MAX_EXPORT_BYTES) { "Export too large" }
        export.output.write(bytes)
        export.bytes += bytes.size.toLong()
    }

    fun finish(id: String): String {
        val export = open[id] ?: throw IllegalArgumentException("Unknown export")
        export.output.fd.sync()
        export.output.close()
        open.remove(id)
        return export.file.absolutePath
    }

    fun abort(id: String) {
        val export = open.remove(id) ?: return
        runCatching { export.output.close() }
        runCatching { export.file.delete() }
    }

    fun delete(path: String): Boolean {
        val file = File(path)
        if (!isOwned(file)) return false
        return !file.exists() || file.delete()
    }

    fun sweepStale(nowMillis: Long = System.currentTimeMillis()): Int {
        ensureRoot()
        var deleted = 0
        root.listFiles()?.forEach { file ->
            if (file.isFile &&
                file.name.matches(STAGED_FILE) &&
                nowMillis - file.lastModified() >= MAX_AGE_MILLIS &&
                file.delete()
            ) {
                deleted += 1
            }
        }
        return deleted
    }

    fun cleanupAll(): Int {
        open.values.forEach { export -> runCatching { export.output.close() } }
        open.clear()
        ensureRoot()
        var deleted = 0
        root.listFiles()?.forEach { file ->
            if (file.isFile && file.name.matches(STAGED_FILE) && file.delete()) deleted += 1
        }
        return deleted
    }

    private fun ensureRoot() {
        check((root.exists() && root.isDirectory) || root.mkdirs())
        restrictToOwner(root)
    }

    private fun restrictToOwner(file: File) {
        file.setReadable(false, false)
        file.setWritable(false, false)
        file.setExecutable(false, false)
        check(file.setReadable(true, true))
        check(file.setWritable(true, true))
        if (file.isDirectory) check(file.setExecutable(true, true))
    }

    private fun isOwned(file: File): Boolean =
        runCatching {
            file.canonicalFile.parentFile == root.canonicalFile &&
                file.name.matches(STAGED_FILE)
        }.getOrDefault(false)

    private companion object {
        // share_plus exposes this cache subtree through its narrow FileProvider
        // path and does not create a second plaintext copy for files already here.
        const val DIRECTORY_NAME = "share_plus"
        const val MAX_AGE_MILLIS = 24L * 60L * 60L * 1000L
        const val MAX_CHUNK_BYTES = 256 * 1024
        const val MAX_EXPORT_BYTES = 50L * 1024L * 1024L
        val EXTENSION = Regex("^[a-z0-9]{1,10}$")
        val STAGED_FILE = Regex("^[0-9a-fA-F-]{36}\\.[a-z0-9]{1,10}$")
    }

    private data class OpenExport(
        val file: File,
        val output: FileOutputStream,
        var bytes: Long = 0,
    )
}
