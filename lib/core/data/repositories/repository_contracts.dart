import '../database.dart';
import '../enums.dart';
import '../daos/transaction_dao.dart';
import 'dashboard_repository.dart';

abstract interface class AccountsRepository {
  Future<List<Account>> getAll();
  Stream<List<Account>> watchAll();
  Future<Account?> getById(int id);
  Future<Account> create({
    required String name,
    required AccountType type,
    String currency,
    int openingBalance,
  });
  Future<void> delete(int id);
}

abstract interface class CategoriesRepository {
  Future<List<Category>> getAll();
  Stream<List<Category>> watchAll();
  Future<List<Category>> getByType(CategoryType type);
  Future<Category?> getById(int id);
  Future<Category> create({
    required String name,
    required CategoryType type,
    String? color,
    String? icon,
  });
  Future<void> delete(int id);
}

abstract interface class TransactionsRepository {
  Future<List<Transaction>> getFiltered(
    TransactionFilter filter, {
    TransactionSort sort,
  });
  Stream<List<Transaction>> watchFiltered(
    TransactionFilter filter, {
    TransactionSort sort,
  });
  Future<Transaction?> getById(int id);
  Future<Transaction> add({
    required TransactionType type,
    required int amount,
    required int accountId,
    required int categoryId,
    required DateTime date,
    String? description,
  });
  Future<Transaction> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required DateTime date,
    String? description,
  });
  Future<void> delete(int id);
  Future<int> balanceForAccount(int accountId);
  Future<int> totalIncome({DateTime? from, DateTime? to});
  Future<int> totalExpense({DateTime? from, DateTime? to});
}

abstract interface class DashboardData {
  Future<BalanceSummary> totalBalance(String targetCurrency);
  Future<List<Transaction>> recentTransactions(int limit);
}
