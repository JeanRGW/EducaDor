import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../gestor/widgets.dart' show DataSkeleton, DataErrorCard;

abstract class EmployeeStyles {
  static ThemeData theme(
    ThemeData base,
  ) => AdminStyles.formTheme(base).copyWith(
    textTheme: base.textTheme.copyWith(bodyMedium: AdminStyles.body),
    colorScheme: base.colorScheme.copyWith(primary: AppColors.successDarkGreen),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: AppColors.surface,
      titleSpacing: 16,
      titleTextStyle: AdminStyles.pageTitle,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.successDarkGreen,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.successDarkGreen,
        minimumSize: const Size(0, 44),
      ),
    ),
  );
}

class EmployeeResult<T> extends StatelessWidget {
  final AsyncValue<T> result;
  final VoidCallback retry;
  final Widget Function(T value) builder;
  const EmployeeResult({
    super.key,
    required this.result,
    required this.retry,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) {
    if (result.asData case final data?) return builder(data.value);
    if (result.hasError) {
      return DataErrorCard(
        message:
            'Não foi possível carregar. Verifique sua conexão ou seu perfil.',
        retry: retry,
      );
    }
    return const DataSkeleton();
  }
}

class LearningCover extends StatelessWidget {
  final String? url;
  final double height, width;
  const LearningCover({super.key, this.url, this.height = 72, this.width = 72});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: height,
      width: width,
      child: url == null
          ? _fallback()
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const ColoredBox(color: AppColors.chipBg),
            ),
    ),
  );
  Widget _fallback() => const ColoredBox(
    color: AppColors.successBg,
    child: SvgIcon(AppIcons.book, color: AppColors.successDarkGreen, size: 32),
  );
}

class LearningCard extends StatelessWidget {
  final LearningItem course;
  final bool compact;
  const LearningCard({super.key, required this.course, this.compact = false});
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(12),
    onTap: () => context.push('/funcionario/course/${course.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          LearningCover(
            url: course.coverUrl,
            width: double.infinity,
            height: 90,
          ),
          const SizedBox(height: 10),
          Text(
            course.title,
            style: AdminStyles.cardTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ] else
          Row(
            children: [
              LearningCover(url: course.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title, style: AdminStyles.formTitle),
                    const SizedBox(height: 4),
                    Text(
                      '${course.lessonCount} ${course.lessonCount == 1 ? 'aula' : 'aulas'}',
                      style: AdminStyles.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(switch (course.state) {
                'completed' => 'Concluído',
                'in_progress' => 'Em andamento',
                _ => 'Disponível',
              }, style: AdminStyles.fieldLabel),
            ),
            if (!compact)
              Text(
                '${(course.progress * 100).round()}%',
                style: AdminStyles.fieldLabel.copyWith(
                  color: AppColors.successDarkGreen,
                ),
              ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          ProgressBar(
            course.progress,
            color: AppColors.successDarkGreen,
            height: 6,
          ),
        ],
      ],
    ),
  );
}

void employeeMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
String employeeDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
