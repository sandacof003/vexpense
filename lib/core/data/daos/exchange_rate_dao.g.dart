// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exchange_rate_dao.dart';

// ignore_for_file: type=lint
mixin _$ExchangeRateDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $ExchangeRatesTable get exchangeRates => attachedDatabase.exchangeRates;
  ExchangeRateDaoManager get managers => ExchangeRateDaoManager(this);
}

class ExchangeRateDaoManager {
  final _$ExchangeRateDaoMixin _db;
  ExchangeRateDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$ExchangeRatesTableTableManager get exchangeRates =>
      $$ExchangeRatesTableTableManager(_db.attachedDatabase, _db.exchangeRates);
}
