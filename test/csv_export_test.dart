import 'dart:convert';

import 'package:educador/features/reports/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV uses BOM, CRLF, quotes and neutralizes formulas', () {
    final bytes = encodeCsv([
      ['Olá, "mundo"\nlinha', ' \t=1+1', '+2', '-3', '@cmd', 'normal'],
    ]);
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(
      utf8.decode(bytes.skip(3).toList()),
      '"Olá, ""mundo""\nlinha","\' \t=1+1","\'+2","\'-3","\'@cmd","normal"\r\n',
    );
  });

  test('filenames do not contain paths', () {
    expect(reportFilename('../A/B', DateTime(2026, 1, 2)), 'a-b-20260102.csv');
  });

  test('reads every page including a full last page', () async {
    final offsets = <int>[];
    final result = await readAllPages<int>((offset) async {
      offsets.add(offset);
      return offset < 100 ? List.generate(50, (i) => offset + i) : [];
    }, () => true);
    expect(result.length, 100);
    expect(offsets, [0, 50, 100]);
  });

  test('aborts if context changes during a read', () async {
    var valid = true;
    expect(
      () => readAllPages<int>((_) async {
        valid = false;
        return [1];
      }, () => valid),
      throwsStateError,
    );
  });
}
