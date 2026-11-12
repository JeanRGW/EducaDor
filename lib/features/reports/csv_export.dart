import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../data/models/models.dart';

String csvCell(String value) {
  // Spreadsheet apps may ignore leading whitespace before interpreting formulas.
  if (RegExp(r'^[\s\u0000-\u001f]*[=+\-@]').hasMatch(value) ||
      RegExp(r'^[\t\r\n]').hasMatch(value)) {
    value = "'$value";
  }
  return '"${value.replaceAll('"', '""')}"';
}

Uint8List encodeCsv(Iterable<List<String>> rows) => Uint8List.fromList([
  0xef,
  0xbb,
  0xbf,
  ...utf8.encode(
    '${rows.map((row) => row.map(csvCell).join(';')).join('\r\n')}\r\n',
  ),
]);

String reportFilename(String report, DateTime date) {
  final safe = report
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  final day =
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  return '${safe.isEmpty ? 'relatorio' : safe}-$day.csv';
}

class ExportTooLarge implements Exception {
  const ExportTooLarge();
}

/// The report changed between pages or between the two export passes.
class ExportChanged implements Exception {
  const ExportChanged();
}

/// Largest CSV the app assembles in memory.
const exportRowCap = 1000;

/// Reads a complete export twice and returns it only when both passes match.
///
/// Each RPC page is a single database snapshot and re-checks authorization.
/// The two passes detect rows inserted, deleted or changed between reads, but
/// they do not provide an atomic snapshot: a value that changes and reverts
/// between both reads is not detectable. Pages are capped at 50 rows and the
/// complete result is capped at [cap] rows.
Future<List<T>> collectStableExport<T>({
  required Future<ExportPage<T>> Function(String? after) fetchPage,
  required String Function(T item) keyOf,
  required List<Object?> Function(T item) fieldsOf,
  int cap = exportRowCap,
}) async {
  Future<List<T>> pass() async {
    final rows = <T>[];
    final keys = <String>{};
    int? total;
    String? after;
    while (true) {
      final page = await fetchPage(after);
      if (page.total < 0 || page.total > cap) throw const ExportTooLarge();
      if (page.limit > 50 ||
          page.items.length > page.limit ||
          (total != null && total != page.total)) {
        throw const ExportChanged();
      }
      total = page.total;
      for (final row in page.items) {
        final key = keyOf(row);
        if ((after != null && key.compareTo(after) <= 0) ||
            !keys.add(key) ||
            rows.length >= total) {
          throw const ExportChanged();
        }
        after = key;
        rows.add(row);
      }
      if (rows.length == total) return rows;
      if (page.items.isEmpty || page.items.length < page.limit) {
        throw const ExportChanged();
      }
      after = keyOf(page.items.last);
    }
  }

  final first = await pass();
  final second = await pass();
  if (first.length != second.length) throw const ExportChanged();
  for (var i = 0; i < first.length; i++) {
    if (keyOf(first[i]) != keyOf(second[i])) throw const ExportChanged();
    final before = fieldsOf(first[i]);
    final after = fieldsOf(second[i]);
    if (before.length != after.length) throw const ExportChanged();
    for (var field = 0; field < before.length; field++) {
      if (before[field] != after[field]) throw const ExportChanged();
    }
  }
  return first;
}

Future<void> saveCsv(String filename, Uint8List bytes) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar CSV',
    fileName: filename,
    bytes: bytes,
  );
}
