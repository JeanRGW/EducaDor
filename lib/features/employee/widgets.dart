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
    textTheme: base.textTheme.copyWith(
      bodyMedium: AdminStyles.bodyFor(
        base.colorScheme,
      ).copyWith(color: base.colorScheme.onSurfaceVariant),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: base.colorScheme.surface,
      titleSpacing: 16,
      titleTextStyle: AdminStyles.pageTitleFor(
        base.colorScheme,
      ).copyWith(color: base.colorScheme.onSurface),
      shape: Border(bottom: BorderSide(color: base.colorScheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: base.colorScheme.successForeground,
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
  final double borderRadius;
  const LearningCover({
    super.key,
    this.url,
    this.height = 72,
    this.width = 72,
    this.borderRadius = 10,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(
      height: height,
      width: width,
      child: url == null
          ? _fallback(context)
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(context),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
            ),
    ),
  );
  Widget _fallback(BuildContext context) => ColoredBox(
    color: context.successSurface,
    child: SvgIcon(
      AppIcons.book,
      color: Theme.of(context).colorScheme.successForeground,
      size: 32,
    ),
  );
}

class LearningCard extends StatelessWidget {
  final LearningItem course;
  final bool compact;
  final Color progressColor;
  const LearningCard({
    super.key,
    required this.course,
    this.compact = false,
    this.progressColor = AppColors.primary,
  });
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
            style: AdminStyles.cardTitle(context).copyWith(fontSize: 12),
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
                    Text(course.title, style: AdminStyles.cardTitle(context)),
                    const SizedBox(height: 4),
                    Text(
                      '${course.lessonCount} ${course.lessonCount == 1 ? 'aula' : 'aulas'}',
                      style: AdminStyles.body(context),
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
              child: Text(
                switch (course.state) {
                  'completed' => 'Concluído',
                  'in_progress' => 'Em andamento',
                  _ => 'Disponível',
                },
                style: AdminStyles.fieldLabel(context).copyWith(
                  color: compact
                      ? Theme.of(context).colorScheme.successForeground
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (!compact)
              Text(
                '${(course.progress * 100).round()}%',
                style: AdminStyles.fieldLabel(context).copyWith(
                  color: course.state == 'completed'
                      ? Theme.of(context).colorScheme.successForeground
                      : progressColor,
                ),
              ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          ProgressBar(course.progress, color: progressColor, height: 6),
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
