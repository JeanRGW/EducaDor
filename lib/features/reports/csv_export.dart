import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

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
    '${rows.map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n',
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

Future<List<T>> readAllPages<T>(
  Future<List<T>> Function(int offset) read,
  bool Function() valid,
) async {
  final result = <T>[];
  for (var offset = 0; offset <= 100000; offset += 50) {
    if (!valid()) throw StateError('Context changed');
    final page = await read(offset);
    if (!valid()) throw StateError('Context changed');
    if (page.length > 50) throw StateError('Invalid page');
    result.addAll(page);
    if (page.length < 50) return result;
  }
  throw StateError('Report exceeds export limit');
}

Future<void> saveCsv(String filename, Uint8List bytes) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar CSV',
    fileName: filename,
    bytes: bytes,
  );
}
