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

  /// Registers the FAB owned by [owner]. A **newly-seen** owner is pushed to
  /// the top and becomes [current]. An **existing** owner has its `fab`
  /// updated **in place** — it does NOT jump back to the top.
  ///
  /// This makes ownership "most-recently-**mounted** wins" rather than
  /// "most-recently-**updated** wins": a page that is currently covered (e.g.
  /// a vault detail sitting under a pushed API-keys / Audit screen) may
  /// rebuild and re-register its FAB, but it must not steal the FAB from the
  /// page covering it. When the covering page pops, its registrar [clear]s and
  /// the covered page's entry resurfaces automatically — so a covered page
  /// never needs (and is never allowed) to re-assert itself to the top.
  ///
  /// Pass `null` for [fab] to claim (or keep) a slot with no FAB.
  ///
  /// Returns `true` when [current] may have changed and the shell should
  /// rebuild; `false` when the visible FAB is unaffected (a no-op, or an
  /// update to a non-top owner).
  bool set(Widget? fab, Object owner) {
    final index = _indexOf(owner);
    if (index != -1) {
      if (identical(_entries[index].fab, fab)) return false;
      _entries[index] = _FabEntry(owner, fab);
      // The visible FAB only changes when the updated owner is on top.
      return index == _entries.length - 1;
    }
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
