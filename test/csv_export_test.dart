import 'dart:convert';

import 'package:educador/data/models/models.dart';
import 'package:educador/features/reports/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row {
  final int id;
  final String value;
  const _Row(this.id, [this.value = 'stable']);
}

/// Serves each complete pass from [passes]; fails on extra requests.
class _Source {
  final List<List<_Row>> passes;
  int _pass = 0;
  final requests = <String?>[];

  _Source(this.passes);

  Future<ExportPage<_Row>> page(String? after) async {
    requests.add(after);
    final rows = passes[_pass];
    final start = after == null
        ? 0
        : rows.indexWhere((row) => row.id.toString().padLeft(4, '0') == after) + 1;
    final end = (start + 50).clamp(0, rows.length);
    final items = rows.sublist(start, end);
    if (end == rows.length) _pass++;
    return ExportPage(total: rows.length, items: items);
  }
}

List<_Row> _rows(int count) => List.generate(count, (i) => _Row(i, 'row-$i'));

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

  for (final count in [0, 49, 50, 51, 101, 1000]) {
    test('stable export reads $count rows in two complete passes', () async {
      final rows = _rows(count);
      final source = _Source([rows, rows]);
      final result = await collectStableExport<_Row>(
        fetchPage: source.page,
        keyOf: (row) => row.id.toString().padLeft(4, '0'),
        fieldsOf: (row) => [row.id, row.value],
      );
      expect(result.map((row) => row.id), rows.map((row) => row.id));
      expect(source.requests, [
        for (var pass = 0; pass < 2; pass++)
          for (var start = 0; start < (count == 0 ? 50 : count); start += 50)
            if (start == 0) null else '${start - 1}'.padLeft(4, '0'),
      ]);
    });
  }

  test(
    'rejects more than the 1,000 row cap before reading all pages',
    () async {
      final rows = _rows(1001);
      final source = _Source([rows, rows]);
      await expectLater(
        collectStableExport<_Row>(
          fetchPage: source.page,
          keyOf: (row) => row.id.toString().padLeft(4, '0'),
          fieldsOf: (row) => [row.id],
        ),
        throwsA(isA<ExportTooLarge>()),
      );
      expect(source.requests, hasLength(1));
    },
  );

  test('rejects a value change with the same count and IDs', () async {
    final first = _rows(60);
    final second = [...first]..[10] = const _Row(10, 'changed');
    final source = _Source([first, second]);
    await expectLater(
      collectStableExport<_Row>(
        fetchPage: source.page,
        keyOf: (row) => row.id.toString().padLeft(4, '0'),
        fieldsOf: (row) => [row.id, row.value],
      ),
      throwsA(isA<ExportChanged>()),
    );
  });

  test('rejects an insertion and a deletion between passes', () async {
    for (final second in [
      [..._rows(60), const _Row(60)],
      _rows(60).where((row) => row.id != 7).toList(),
    ]) {
      final source = _Source([_rows(60), second]);
      await expectLater(
        collectStableExport<_Row>(
          fetchPage: source.page,
          keyOf: (row) => row.id.toString().padLeft(4, '0'),
          fieldsOf: (row) => [row.id, row.value],
        ),
        throwsA(isA<ExportChanged>()),
      );
    }
  });

  test('rejects duplicate IDs and short non-final pages', () async {
    await expectLater(
      collectStableExport<_Row>(
        fetchPage: (_) async =>
            const ExportPage(total: 2, items: [_Row(1), _Row(1)]),
        keyOf: (row) => row.id.toString().padLeft(4, '0'),
        fieldsOf: (row) => [row.id],
      ),
      throwsA(isA<ExportChanged>()),
    );
    await expectLater(
      collectStableExport<_Row>(
        fetchPage: (after) async =>
            ExportPage(total: 3, items: after == null ? _rows(2) : []),
        keyOf: (row) => row.id.toString().padLeft(4, '0'),
        fieldsOf: (row) => [row.id],
      ),
      throwsA(isA<ExportChanged>()),
    );
  });

  test('a failing page aborts without opening a save dialog', () async {
    var calls = 0;
    await expectLater(
      collectStableExport<_Row>(
        fetchPage: (_) async {
          calls++;
          throw StateError('offline');
        },
        keyOf: (row) => row.id.toString().padLeft(4, '0'),
        fieldsOf: (row) => [row.id],
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 1);
  });
}
