import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/services/csv/csv_import_models.dart';

/// Seam file picker — di-override dari test supaya tidak bergantung plugin
/// native. Produksi: [FilePicker.pickFiles] khusus ekstensi `.csv`.
typedef PickCsvFile = Future<FilePickerResult?> Function();

PickCsvFile pickCsvFile = () => FilePicker.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['csv'],
  withData: true,
);

/// Import CSV FE-08: pilih file → preview (valid/invalid/duplikat + rencana
/// akun & kategori baru) → satu operasi import atomik → summary hasil.
///
/// Parsing/validasi/dedupe/mapping semuanya di [CsvImportRepository] (BE-06);
/// layar ini hanya merender hasilnya. Summary sukses hanya tampil setelah
/// Future `importBytes` selesai — tidak pernah klaim sukses lebih awal.
class ImportCsvScreen extends ConsumerStatefulWidget {
  const ImportCsvScreen({super.key});

  static const path = '/import';

  @override
  ConsumerState<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

class _ImportCsvScreenState extends ConsumerState<ImportCsvScreen> {
  String? _fileName;
  List<int>? _bytes;
  bool _previewing = false;
  CsvImportPreview? _preview;
  bool _importing = false;
  CsvImportReport? _report;
  String? _error;

  Future<void> _pick() async {
    FilePickerResult? result;
    try {
      result = await pickCsvFile();
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memilih file: $e');
      return;
    }
    // Batal = tidak ada perubahan state sama sekali.
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    List<int> bytes;
    try {
      bytes = file.bytes ?? await File(file.path!).readAsBytes();
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membaca file: $e');
      return;
    }

    setState(() {
      _fileName = file.name;
      _bytes = bytes;
      _preview = null;
      _report = null;
      _error = null;
      _previewing = true;
    });
    try {
      final preview = await ref
          .read(csvImportRepositoryProvider)
          .preview(bytes: bytes, fileName: file.name);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memproses CSV: $e');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _import() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _importing = true;
      _report = null;
      _error = null;
    });
    try {
      final report = await ref
          .read(csvImportRepositoryProvider)
          .importBytes(bytes: bytes, fileName: _fileName);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      // Atomic: gagal = rollback penuh, tidak ada sukses sebagian.
      if (mounted) {
        setState(() => _error = 'Import gagal (tidak ada data masuk): $e');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final report = _report;
    final canImport =
        !_previewing && !_importing && preview != null && !preview.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Import CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            key: const Key('import.pick.button'),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Pilih file CSV'),
            onPressed: (_previewing || _importing) ? null : _pick,
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 8),
            Text(
              'File: $_fileName',
              key: const Key('import.file.name'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _Message(
              keyName: 'import.error',
              text: _error!,
              color: theme.colorScheme.error,
            ),
          ],
          if (_previewing || _importing) ...[
            const SizedBox(height: 24),
            const Center(
              child: CircularProgressIndicator(
                key: Key('import.loading'),
              ),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 16),
            _PreviewSection(preview: preview),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('import.button'),
              icon: const Icon(Icons.download_done_outlined),
              label: const Text('Import'),
              onPressed: canImport ? _import : null,
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 16),
            _ReportSection(report: report),
          ],
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.preview});

  final CsvImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = preview.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const Key('import.preview'),
      children: [
        Text('Preview', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Total ${summary.totalRows} baris • Valid ${summary.validRows} • '
          'Duplikat ${summary.duplicateRows} • Invalid ${summary.invalidRows}',
          key: const Key('import.preview.summary'),
          style: theme.textTheme.bodyMedium,
        ),
        if (preview.accountsToCreate.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Akun baru: ${preview.accountsToCreate.join(', ')}',
            key: const Key('import.preview.accounts'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (preview.categoriesToCreate.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Kategori baru: ${preview.categoriesToCreate.join(', ')}',
            key: const Key('import.preview.categories'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (preview.errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Baris gagal/skip (tidak di-import):',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          for (final error in preview.errors)
            Text(
              '- $error',
              key: Key('import.preview.error.${error.rowNumber}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.report});

  final CsvImportReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const Key('import.report'),
      children: [
        Text('Hasil import', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${report.insertedRows} transaksi masuk, '
          '${report.createdAccounts} akun dibuat, '
          '${report.createdCategories} kategori dibuat, '
          '${report.errors.length} gagal/skip',
          key: const Key('import.report.summary'),
          style: theme.textTheme.bodyMedium,
        ),
        if (report.errors.isNotEmpty)
          for (final error in report.errors)
            Text(
              '- $error',
              key: Key('import.report.error.${error.rowNumber}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.keyName, required this.text, required this.color});

  final String keyName;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    key: Key(keyName),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
  );
}
