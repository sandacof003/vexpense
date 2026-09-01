/// Deteksi & normalisasi encoding untuk import CSV.
///
/// PRD §7: file harus UTF-8 atau Windows-1252. Karena Dart `String` internal
/// UTF-16, kita perlu memastikan byte input di-decode dengan benar. Strategi
/// sederhana: coba decode strict UTF-8; bila gagal (byte invalid) anggap
/// Windows-1252. BOM UTF-8 di-strip.
library;

import 'dart:convert';

/// Status encoding hasil deteksi.
enum CsvEncoding {
  /// UTF-8 valid (termasuk UTF-8 with BOM).
  utf8,

  /// Tidak valid sebagai UTF-8 -> diasumsikan Windows-1252.
  windows1252,
}

/// Hasil deteksi encoding.
class CsvEncodingResult {
  const CsvEncodingResult(this.encoding, this.decoded);

  final CsvEncoding encoding;

  /// Konten yang sudah di-decode jadi String (BOM sudah dibuang).
  final String decoded;
}

/// Deteksi & decode konten CSV dari bytes.
///
/// Catatan: deteksi ini heuristik — UTF-8 valid diutamakan; byte yang
/// melanggar aturan UTF-8 diperlakukan sebagai Windows-1252. Untuk file
/// yang secara teknis valid UTF-8 tapi sebenarnya Latin-1, hasilnya bisa
/// berbeda; itu edge case yang tidak di-cover MVP (dicatat sebagai batasan).
class CsvEncodingDetector {
  const CsvEncodingDetector();

  CsvEncodingResult detect(List<int> bytes) {
    final str = _decodeUtf8Strict(bytes);
    if (str != null) {
      return CsvEncodingResult(CsvEncoding.utf8, _stripBom(str));
    }
    final decoded1252 = latin1.decode(bytes, allowInvalid: true);
    return CsvEncodingResult(CsvEncoding.windows1252, _stripBom(decoded1252));
  }

  /// Decode strict: null bila ada byte invalid untuk UTF-8.
  String? _decodeUtf8Strict(List<int> bytes) {
    try {
      // allowMalformed: false -> FormatException pada byte invalid.
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  String _stripBom(String s) {
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
      return s.substring(1);
    }
    return s;
  }
}
