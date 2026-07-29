import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_entries_tab.dart';

void main() {
  test('website icon resolution includes entries beyond the render window', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final entries = List<EntryEntity>.generate(
      539,
      (index) => EntryEntity(
        id: 'entry-$index',
        vaultId: 'vault',
        label: 'Entry $index',
        icon: 'website:host-$index.example.com',
        type: EntryType.credential,
        createdAt: epoch,
        updatedAt: epoch,
        lifecycleState: MemberEntryState.active,
        currentRevision: '1',
      ),
    );

    final hostnames = websiteIconHostnames(entries);

    expect(hostnames, hasLength(539));
    expect(hostnames, contains('host-538.example.com'));
  });

  test('website icon resolution deduplicates hosts and ignores presets', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    EntryEntity entry(String id, String? icon) => EntryEntity(
      id: id,
      vaultId: 'vault',
      label: id,
      icon: icon,
      type: EntryType.credential,
      createdAt: epoch,
      updatedAt: epoch,
      lifecycleState: MemberEntryState.active,
      currentRevision: '1',
    );

    expect(
      websiteIconHostnames([
        entry('one', 'website:example.com'),
        entry('two', 'website:example.com'),
        entry('three', 'lock'),
        entry('four', null),
      ]),
      ['example.com'],
    );
  });
}
