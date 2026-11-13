import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';

abstract class CompanyStyles {
  static ThemeData theme(
    ThemeData base,
  ) => AdminStyles.formTheme(base).copyWith(
    textTheme: AdminStyles.formTheme(base).textTheme.copyWith(
      bodyMedium: AdminStyles.bodyFor(base.colorScheme),
      labelLarge: AdminStyles.fieldLabelFor(base.colorScheme),
    ),
    appBarTheme: AdminStyles.formTheme(base).appBarTheme.copyWith(
      titleTextStyle: AdminStyles.pageTitleFor(base.colorScheme),
      titleSpacing: 16,
      shape: const Border(),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: base.colorScheme.successForeground,
        minimumSize: const Size(0, 44),
        textStyle: AdminStyles.fieldLabelFor(base.colorScheme),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: base.colorScheme.primary,
        side: BorderSide(color: base.colorScheme.outlineVariant),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AdminStyles.fieldLabelFor(base.colorScheme),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: base.colorScheme.primary,
        foregroundColor: base.colorScheme.onPrimary,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AdminStyles.fieldLabelFor(base.colorScheme),
      ),
    ),
  );

  static TextStyle caption(BuildContext context) => TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 11,
    color: Theme.of(context).colorScheme.outline,
    height: 1.4,
  );
}

String companyInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(3)
    .map((part) => part[0])
    .join()
    .toUpperCase();

class CompanyAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final bool outlined;
  final Color? foregroundColor;
  const CompanyAvatar({
    super.key,
    required this.initials,
    this.size = 40,
    this.outlined = false,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.successSurface,
      shape: BoxShape.circle,
      border: outlined
          ? Border.all(
              color: foregroundColor ?? context.successForeground,
              width: 2,
            )
          : null,
    ),
    child: Text(
      initials,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: AppFonts.outfit,
        fontSize: size * 0.34,
        fontWeight: FontWeight.w700,
        color: foregroundColor ?? context.successForeground,
      ),
    ),
  );
}

class CompanyBadge extends StatelessWidget {
  final String label;
  final bool warning;
  const CompanyBadge(this.label, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: warning ? context.dangerSurface : context.activeSurface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: CompanyStyles.caption(context).copyWith(
        fontWeight: FontWeight.w600,
        color: warning
            ? context.dangerForeground
            : Theme.of(context).colorScheme.successForeground,
      ),
    ),
  );
}

class CompanyErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const CompanyErrorCard({
    super.key,
    required this.message,
    required this.retry,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: AdminStyles.body(context)),
        TextButton(onPressed: retry, child: const Text('Tentar novamente')),
      ],
    ),
  );
}

void showCompanyUnavailable(BuildContext context, String feature) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature ainda não está disponível.')),
    );
