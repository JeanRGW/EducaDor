import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/common.dart';

const monthNames = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

String monthLabel(DateTime date) => monthNames[date.month - 1];

String formatCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]}.',
);

String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} '
    '${monthLabel(date)} ${date.year}';

class CompanyFieldRow extends StatelessWidget {
  final Widget first;
  final Widget second;
  final int firstFlex;
  const CompanyFieldRow({
    super.key,
    required this.first,
    required this.second,
    this.firstFlex = 1,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(12) > 16) {
        return Column(children: [first, second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: firstFlex, child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );
}

class DataErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const DataErrorCard({super.key, required this.message, required this.retry});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      children: [
        Text(message),
        TextButton(onPressed: retry, child: const Text('Tentar novamente')),
      ],
    ),
  );
}

class DataSkeleton extends StatelessWidget {
  final bool chart;
  const DataSkeleton({super.key, this.chart = false});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando dados',
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final height in chart ? [18.0, 140.0] : [18.0, 28.0, 14.0]) ...[
            SizedBox(
              height: height,
              width: double.infinity,
              child: const ColoredBox(color: AppColors.chipBg),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
