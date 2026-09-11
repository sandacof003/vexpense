class Money {
  const Money({required this.minorUnit, required this.currency});

  final int minorUnit;
  final String currency;

  Money copyWith({int? minorUnit, String? currency}) => Money(
    minorUnit: minorUnit ?? this.minorUnit,
    currency: currency ?? this.currency,
  );
}
