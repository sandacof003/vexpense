import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/repositories/repository_contracts.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/services/csv/csv_import_models.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/settings/import_csv_screen.dart';

/// Test FE-08: layar import CSV — pilih file → preview → import → summary.
///
/// `pickCsvFile` (seam di screen) di-fake supaya test tidak bergantung plugin
/// native. Preview/report pakai repository asli di atas DB in-memory untuk
/// jalur end-to-end, dan repository palsu ber-gate untuk membuktikan summary
/// hanya tampil SETELAH Future import selesai.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  FilePickerResult pickResult(String name, List<int> bytes) =>
      FilePickerResult([
        PlatformFile(name: name, size: bytes.length, bytes: Uint8List.fromList(bytes)),
      ]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() async {
    pickCsvFile = _defaultPickCsvFile;
    container.dispose();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester, {List<Override> extra = const []}) async {
    final scoped = ProviderScope(
      overrides: extra,
      child: const MaterialApp(home: ImportCsvScreen()),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: scoped),
    );
    await tester.pump();
  }

  /// Teardown widget tree + flush timer drift (pola dashboard_screen_test).
  Future<void> settleDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  const validCsv =
      'Date,Type,Category,Account,Amount,Currency,Note\n'
      '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n'
      '2024-01-16,income,Gaji,BCA,5000000,IDR,gaji januari\n'
      '2024-01-17,expense,Transport,Cash,15000,IDR,\n'
      'bukan-tanggal,expense,Makan,Cash,10000,IDR,invalid\n';

  testWidgets('pilih file → preview tampil: summary, akun/kategori baru, baris invalid', (tester) async {
    pickCsvFile = () async => pickResult('mutasi.csv', utf8.encode(validCsv));
    await pumpScreen(tester);

    // Sebelum pilih: tidak ada preview, tidak ada tombol Import.
    expect(find.byKey(const Key('import.preview')), findsNothing);
    expect(find.byKey(const Key('import.button')), findsNothing);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import.file.name')), findsOneWidget);
    expect(find.text('File: mutasi.csv'), findsOneWidget);
    final summary = tester
        .widget<Text>(find.byKey(const Key('import.preview.summary')))
        .data!;
    expect(summary, contains('Total 4 baris'));
    expect(summary, contains('Valid 3'));
    expect(summary, contains('Invalid 1'));
    // Akun/kategori baru (Cash, BCA, Makan belum ada di DB seed).
    expect(
      tester.widget<Text>(find.byKey(const Key('import.preview.accounts'))).data,
      contains('Cash'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('import.preview.categories'))).data,
      contains('Makan'),
    );
    // Baris invalid JELAS terlihat, tidak di-skip diam-diam.
    expect(find.byKey(const Key('import.preview.error.4')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('import.preview.error.4'))).data,
      contains('baris 4'),
    );

    await settleDown(tester);
  });

  testWidgets('batal pilih file = tidak ada perubahan state', (tester) async {
    pickCsvFile = () async => null;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import.preview')), findsNothing);
    expect(find.byKey(const Key('import.error')), findsNothing);

    await settleDown(tester);
  });

  testWidgets('file tidak valid (header salah) → error terlihat, Import disabled', (tester) async {
    pickCsvFile = () async =>
        pickResult('rusak.csv', utf8.encode('A,B,C\n1,2,3\n'));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();

    // Error tingkat-file muncul di daftar error preview.
    expect(find.byKey(const Key('import.preview.error.null')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('import.button')),
    );
    expect(button.onPressed, isNull); // tidak ada baris valid → tidak bisa import

    await settleDown(tester);
  });

  testWidgets('preview gagal → pesan error, tidak crash', (tester) async {
    pickCsvFile = () async => pickResult('x.csv', utf8.encode(validCsv));
    await pumpScreen(tester, extra: [
      csvImportRepositoryProvider.overrideWithValue(_ThrowingRepo()),
    ]);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import.error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('import.error'))).data,
      contains('Gagal memproses CSV'),
    );

    await settleDown(tester);
  });

  testWidgets('summary hanya tampil setelah importBytes selesai', (tester) async {
    final gate = _GatedRepo();
    pickCsvFile = () async => pickResult('mutasi.csv', utf8.encode(validCsv));
    await pumpScreen(tester, extra: [
      csvImportRepositoryProvider.overrideWithValue(gate),
    ]);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import.button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import.button')));
    await tester.pump(); // future masih pending (gate belum dibuka)
    await tester.pump(const Duration(milliseconds: 10));

    // Progress tampil, summary BELUM ada.
    expect(find.byKey(const Key('import.loading')), findsOneWidget);
    expect(find.byKey(const Key('import.report')), findsNothing);
    expect(gate.importCalls, 1);

    gate.open();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import.report')), findsOneWidget);
    final summary = tester
        .widget<Text>(find.byKey(const Key('import.report.summary')))
        .data!;
    expect(summary, contains('2 transaksi masuk'));
    expect(summary, contains('1 akun dibuat'));
    expect(summary, contains('1 kategori dibuat'));
    expect(summary, contains('1 gagal/skip'));

    await settleDown(tester);
  });

  testWidgets('import end-to-end repository asli: baris valid masuk DB satu operasi', (tester) async {
    pickCsvFile = () async => pickResult('mutasi.csv', utf8.encode(validCsv));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('import.pick.button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import.button')));
    await tester.pumpAndSettle();

    final report = tester
        .widget<Text>(find.byKey(const Key('import.report.summary')))
        .data!;
    expect(report, contains('3 transaksi masuk'));
    final inserted = await db.transactionDao.getFiltered(const TransactionFilter());
    expect(inserted.length, 3);

    await settleDown(tester);
  });
}

// Simpan referensi default seam untuk restore di tearDown.
final PickCsvFile _defaultPickCsvFile = pickCsvFile;

final DateTime _date = DateTime.utc(2024, 1, 15);

class _ThrowingRepo implements CsvImportRepository {
  @override
  Future<CsvImportPreview> preview({required List<int> bytes, String? fileName}) =>
      Future.error(StateError('boom'));

  @override
  Future<CsvImportReport> importBytes({required List<int> bytes, String? fileName}) =>
      Future.error(StateError('boom'));
}

/// Repository palsu dengan gate manual: import tidak selesai sebelum [open].
class _GatedRepo implements CsvImportRepository {
  final _completer = Completer<void>();
  int importCalls = 0;

  void open() => _completer.complete();

  @override
  Future<CsvImportPreview> preview({required List<int> bytes, String? fileName}) async =>
      CsvImportPreview(
        result: CsvImportResult(
          rows: [
            CsvParsedRow(
              date: _date,
              rowNumber: 1,
              type: 'expense',
              categoryName: 'Makan',
              accountName: 'Cash',
              amountMinorUnit: 25000,
              currencyCode: 'IDR',
            ),
          ],
          errors: [],
          summary: const CsvImportSummary(
            totalRows: 3,
            validRows: 2,
            duplicateRows: 0,
            invalidRows: 1,
            distinctAccounts: 1,
            distinctCategories: 1,
          ),
        ),
        accountsToCreate: ['Cash'],
        categoriesToCreate: ['Makan'],
      );

  @override
  Future<CsvImportReport> importBytes({required List<int> bytes, String? fileName}) async {
    importCalls++;
    await _completer.future;
    return const CsvImportReport(
      insertedRows: 2,
      createdAccounts: 1,
      createdCategories: 1,
      errors: [
        CsvRowError(
          code: CsvImportErrorCode.invalidDate,
          rowNumber: 3,
          column: 'Date',
          message: 'Tanggal tidak valid',
        ),
      ],
    );
  }
}
