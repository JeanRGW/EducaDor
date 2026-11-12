import 'dart:convert';

import 'package:educador/features/reports/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CSV uses pt-BR delimiter, BOM, CRLF, quotes and neutralizes formulas',
    () {
      final bytes = encodeCsv([
        ['Olá; "mundo"\nlinha', ' \t=1+1', '+2', '-3', '@cmd', '12,5'],
      ]);
      expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
      expect(
        utf8.decode(bytes.skip(3).toList()),
        '"Olá; ""mundo""\nlinha";"\' \t=1+1";"\'+2";"\'-3";"\'@cmd";"12,5"\r\n',
      );
    },
  );

  test('filenames do not contain paths', () {
    expect(reportFilename('../A/B', DateTime(2026, 1, 2)), 'a-b-20260102.csv');
  });

  test('rejects potentially incomplete snapshots, not just duplicates', () {
    expect(requireSingleSnapshot(List.generate(49, (i) => i)), hasLength(49));
    expect(
      () => requireSingleSnapshot(List.generate(50, (i) => i)),
      throwsA(isA<ExportTooLarge>()),
    );
    expect(
      requireSingleSnapshot(List.generate(50, (i) => i), total: 50),
      hasLength(50),
    );
    expect(
      () => requireSingleSnapshot(List.generate(50, (i) => i), total: 51),
      throwsA(isA<ExportTooLarge>()),
    );
    expect(
      () => requireSingleSnapshot([1, 2], total: 3),
      throwsA(isA<ExportTooLarge>()),
    );
  });
}
