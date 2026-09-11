import '../database.dart';
import '../daos/currency_dao.dart';

abstract interface class CurrenciesRepository {
  Future<List<Currency>> getAll();
  Future<Currency?> getByCode(String code);
}

class CurrencyRepository implements CurrenciesRepository {
  const CurrencyRepository(this._dao);

  final CurrencyDao _dao;

  @override
  Future<List<Currency>> getAll() => _dao.getAll();

  @override
  Future<Currency?> getByCode(String code) => _dao.getByCode(code);
}
