import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/data/repositories/repository_contracts.dart';

class FakeAccountsRepository implements AccountsRepository {
  @override
  Future<List<Account>> getAll() async => const [];

  @override
  Stream<List<Account>> watchAll() => Stream.value(const []);

  @override
  Future<Account?> getById(int id) async => null;

  @override
  Future<Account> create({
    required String name,
    required AccountType type,
    String currency = 'IDR',
    int openingBalance = 0,
  }) => throw UnimplementedError();

  @override
  Future<void> update(Account account, {required String newName}) async {}

  @override
  Future<void> delete(int id) async {}
}

void main() {
  test('account provider can be overridden with a fake repository', () async {
    final fake = FakeAccountsRepository();
    final container = ProviderContainer(
      overrides: [accountRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(container.read(accountRepositoryProvider), same(fake));
    expect(await container.read(accountRepositoryProvider).getAll(), isEmpty);
  });
}
