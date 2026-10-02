import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/common.dart';

abstract class CompanyStyles {
  static ThemeData theme(
    ThemeData base,
  ) => AdminStyles.formTheme(base).copyWith(
    textTheme: AdminStyles.formTheme(base).textTheme.copyWith(
      bodyMedium: AdminStyles.body,
      labelLarge: AdminStyles.fieldLabel,
    ),
    appBarTheme: AdminStyles.formTheme(base).appBarTheme.copyWith(
      titleTextStyle: AdminStyles.pageTitle,
      titleSpacing: 16,
      shape: const Border(),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.successDarkGreen,
        minimumSize: const Size(0, 44),
        textStyle: AdminStyles.fieldLabel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.successDarkGreen,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AdminStyles.fieldLabel,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.successDarkGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AdminStyles.fieldLabel,
      ),
    ),
  );

  static const caption = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 11,
    color: AppColors.textMuted,
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
  const CompanyAvatar({
    super.key,
    required this.initials,
    this.size = 40,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.successBg,
      shape: BoxShape.circle,
      border: outlined
          ? Border.all(color: AppColors.successDarkGreen, width: 2)
          : null,
    ),
    child: Text(
      initials,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: AppFonts.outfit,
        fontSize: size * 0.34,
        fontWeight: FontWeight.w700,
        color: AppColors.successDarkGreen,
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
      color: warning ? AppColors.dangerBg : AppColors.successBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: CompanyStyles.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: warning ? AppColors.danger : AppColors.successDarkGreen,
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
        Text(message, style: AdminStyles.body),
        TextButton(onPressed: retry, child: const Text('Tentar novamente')),
      ],
    ),
  );
}

void showCompanyUnavailable(BuildContext context, String feature) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature ainda não está disponível.')),
    );
