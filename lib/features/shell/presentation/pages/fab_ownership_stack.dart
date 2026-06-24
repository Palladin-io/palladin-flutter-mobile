import 'package:flutter/widgets.dart';

/// Ordered ownership stack of shell FAB registrations.
///
/// The shell renders [current] — the top entry's `fab` (which may be
/// `null`). Each page that mounts a `FabRegistrar` owns exactly one entry,
/// keyed by an identity [Object] token.
///
/// The stack — rather than a single slot — is what makes FAB ownership
/// deterministic across `push`/`pop`:
///
///   * When a pushed page registers its FAB, its entry lands on top and
///     becomes visible.
///   * When that page pops and its registrar disposes, [clear] removes the
///     entry and the previously-covered page's FAB resurfaces
///     automatically — no page re-asserts its FAB on return.
///
/// This stops a covered page's FAB from "leaking" onto a page that
/// declares a different (or no) FAB.
class FabOwnershipStack {
  final List<_FabEntry> _entries = <_FabEntry>[];

  /// The FAB that should currently be shown — the top entry's `fab`, or
  /// `null` when the stack is empty or the top entry registered no FAB.
  Widget? get current => _entries.isEmpty ? null : _entries.last.fab;

  /// Number of registrations currently on the stack. Exposed for tests.
  @visibleForTesting
  int get depth => _entries.length;

  /// Registers (or updates) the FAB owned by [owner], moving it to the top
  /// so it becomes [current]. Re-registering an existing owner updates its
  /// `fab` in place. Pass `null` for [fab] to claim the top with no FAB
  /// (suppressing any lower page's FAB).
  ///
  /// Returns `true` when [current] may have changed and the shell should
  /// rebuild; `false` when the call was a no-op (the same owner was
  /// already on top with an identical fab).
  bool set(Widget? fab, Object owner) {
    final index = _indexOf(owner);
    final alreadyOnTop = index != -1 && index == _entries.length - 1;
    if (alreadyOnTop && identical(_entries[index].fab, fab)) return false;
    if (index != -1) _entries.removeAt(index);
    _entries.add(_FabEntry(owner, fab));
    return true;
  }

  /// Removes [owner]'s entry. If it was on top, the next entry down
  /// becomes [current]. No-op (returns `false`) if [owner] is not present.
  bool clear(Object owner) {
    final index = _indexOf(owner);
    if (index == -1) return false;
    _entries.removeAt(index);
    return true;
  }

  int _indexOf(Object owner) =>
      _entries.indexWhere((e) => identical(e.owner, owner));
}

/// A single FAB registration: the registrar [owner] token and the [fab]
/// it wants shown (which may be `null` to suppress any lower FAB).
class _FabEntry {
  const _FabEntry(this.owner, this.fab);

  final Object owner;
  final Widget? fab;
}
