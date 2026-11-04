package io.palladin.mobile.autofill

internal data class AutoFillSourceFence(val epoch: Long, val profile: String, val active: Boolean)
internal class AutoFillSourceException(val code: String) : IllegalStateException(code)

/** Durable source control metadata; no credential, Entry or key material. */
internal class AutoFillSourceAuthority(
    private val read: () -> AutoFillSourceFence?,
    private val write: (AutoFillSourceFence) -> Unit,
) {
    private var session: String? = null
    private var admitted = false

    fun begin(profile: String, session: String): Long = synchronized(AutoFillMutationLock.monitor) {
        require(profile.isNotBlank() && session.isNotBlank())
        this.session = null
        admitted = false
        val epoch = Math.addExact(read()?.epoch ?: 0, 1)
        write(AutoFillSourceFence(epoch, profile, false))
        this.session = session
        epoch
    }

    fun activate(session: String, epoch: Long): Long = synchronized(AutoFillMutationLock.monitor) {
        val current = requireCurrent(session, epoch)
        admitted = false
        write(current.copy(active = true))
        admitted = true
        epoch
    }

    fun invalidate(session: String, epoch: Long): Long = synchronized(AutoFillMutationLock.monitor) {
        val current = requireCurrent(session, epoch)
        admitted = false
        val replacement = current.copy(epoch = Math.addExact(epoch, 1), active = false)
        write(replacement)
        replacement.epoch
    }

    fun current(profile: String, session: String, epoch: Long): Boolean = synchronized(AutoFillMutationLock.monitor) {
        if (!admitted || this.session != session) return@synchronized false
        val value = read() ?: return@synchronized false
        value.active && value.epoch == epoch && value.profile == profile
    }

    fun matches(profile: String, session: String, epoch: Long): Boolean = synchronized(AutoFillMutationLock.monitor) {
        if (this.session != session) return@synchronized false
        val value = read() ?: return@synchronized false
        value.epoch == epoch && value.profile == profile
    }

    fun matchesSession(profile: String, session: String): Boolean = synchronized(AutoFillMutationLock.monitor) {
        this.session == session && read()?.profile == profile
    }

    fun sessionEpoch(profile: String, session: String): Long = synchronized(AutoFillMutationLock.monitor) {
        val value = read() ?: throw AutoFillSourceException("SOURCE_UNAVAILABLE")
        if (!matches(profile, session, value.epoch)) throw AutoFillSourceException("SOURCE_STALE_SESSION")
        value.epoch
    }

    fun snapshot(): AutoFillSourceFence? = synchronized(AutoFillMutationLock.monitor) { read() }

    fun revokeSnapshot(epoch: Long, profile: String): Long = synchronized(AutoFillMutationLock.monitor) {
        val current = read() ?: throw AutoFillSourceException("SOURCE_UNAVAILABLE")
        if (current.epoch != epoch || current.profile != profile) throw AutoFillSourceException("SOURCE_STALE_SNAPSHOT")
        admitted = false
        session = null
        val denied = current.copy(epoch = Math.addExact(epoch, 1), active = false)
        write(denied)
        denied.epoch
    }

    fun lock(session: String) = synchronized(AutoFillMutationLock.monitor) {
        if (this.session == session) { this.session = null; admitted = false }
    }

    private fun requireCurrent(session: String, epoch: Long): AutoFillSourceFence {
        if (this.session != session) throw AutoFillSourceException("SOURCE_STALE_SESSION")
        val current = read() ?: throw AutoFillSourceException("SOURCE_UNAVAILABLE")
        if (current.epoch != epoch) throw AutoFillSourceException("SOURCE_STALE_EPOCH")
        return current
    }
}
