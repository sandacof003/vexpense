import '../../../core/data/enums.dart';

class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.type,
    required this.currency,
    this.openingBalanceMinorUnit = 0,
  });

  final String name;
  final AccountType type;
  final String currency;
  final int openingBalanceMinorUnit;
}
