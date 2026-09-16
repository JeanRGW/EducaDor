import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';

// ---------------------------------------------------------------- Home
class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const AvatarBadge('JS'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Olá, João!',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Row(
                    children: const [
                      SvgIcon(AppIcons.building, size: 13, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text('Grupo Santa Maria',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.successDarkGreen)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  SvgIcon(AppIcons.fire,
                      size: 15, color: AppColors.successDarkGreen),
                  SizedBox(width: 4),
                  Text('5 Dias',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successDarkGreen)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Progress card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Seu progresso de aprendizado',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700))),
                    const Text('25% concluído',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 12),
                const ProgressBar(0.25),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Expanded(
                        child: Text('3 de 12 cursos atribuídos concluídos',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.textMuted))),
                    Text('Restam 9 cursos',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.successDarkGreen)),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Continue aprendendo'),
          AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => context.push('/funcionario/course/crs-saude'),
            child: Column(
              children: [
                Row(
                  children: [
                    const _CourseCover(color: '#7FC3E8', size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Saúde',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          const Text('Vídeo • 5 min restantes',
                              style: TextStyle(
                                  fontSize: 12.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: ProgressBar(0.75, height: 6),
                    ),
                    const SizedBox(width: 10),
                    const Text('75%',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successDarkGreen)),
                  ],
                ),
              ],
            ),
          ),
          SectionHeader('Recomendado para você',
              action: 'Ver tudo', onAction: () => context.go('/funcionario/modulos')),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: _RecommendedCourse(courseId: 'crs-socorro')),
              SizedBox(width: 12),
              Expanded(child: _RecommendedCourse(courseId: 'crs-ergo')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendedCourse extends StatelessWidget {
  final String courseId;
  const _RecommendedCourse({required this.courseId});

  @override
  Widget build(BuildContext context) {
    final c = MockData.courseById(courseId);
    final released = c.status != ContentStatus.locked;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/funcionario/course/${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CourseCover(color: c.coverColor, size: double.infinity, height: 84),
          const SizedBox(height: 10),
          Text(c.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(c.subtitle,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          StatusChip(
            released ? c.statusLabel : c.statusLabel,
            color: released ? AppColors.successDarkGreen : AppColors.warning,
            bg: released ? AppColors.successBg : AppColors.warningBg,
          ),
        ],
      ),
    );
  }
}

/// Colored cover placeholder used for course thumbnails.
class _CourseCover extends StatelessWidget {
  final String color;
  final double size;
  final double? height;

  const _CourseCover({required this.color, this.size = 72, this.height});

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = height ?? size;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorFromHex(color),
            colorFromHex(color).withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: SvgIcon(AppIcons.health,
            color: Colors.white.withValues(alpha: 0.9), size: w >= 100 ? 34 : 22),
      ),
    );
  }
}

// ---------------------------------------------------------------- Modules
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  int _tab = 0; // 0 meu aprendizado, 1 descobrir
  int _chip = 0;

  // The Figma shows this screen's filter chips in brand blue, unlike the
  // teal chips used on the gestor/company screens.
  static const _chipActive = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('MODULOS', style: TextStyle(fontSize: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _toggle('Meu aprendizado', 0),
                  _toggle('Descobrir', 1),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SearchField('Pesquisar conteúdo de aprendizagem...'),
          const SizedBox(height: 14),
          FilterChips(
            options: const ['Todos', 'Vídeos', 'Áudios', 'Quizzes', 'Leitura'],
            selected: _chip,
            onSelected: (i) => setState(() => _chip = i),
            activeColor: _chipActive,
          ),
          const SizedBox(height: 8),
          for (final c in MockData.courses)
            if (c.title != 'Saúde') _ModuleCard(course: c),
        ],
      ),
    );
  }

  Widget _toggle(String label, int index) {
    final active = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: active ? null : Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : AppColors.textMuted)),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final Course course;
  const _ModuleCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/funcionario/course/${course.id}'),
      child: Row(
        children: [
          _CourseCover(color: course.coverColor, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.subtitle,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 2),
                Text(course.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        course.progress >= 100 ? 'Completed' : 'In Progress',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                    Text('${course.progress.round()}%',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successDarkGreen)),
                  ],
                ),
                const SizedBox(height: 6),
                ProgressBar(
                  course.progress / 100,
                  height: 6,
                  color: course.progress >= 100
                      ? AppColors.successDarkGreen
                      : AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Course Detail
class CourseDetailScreen extends StatelessWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context) {
    final course = MockData.courseById(courseId);
    final module = MockData.moduleById('mod-1');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes'),
        leading: IconButton(
          icon: const SvgIcon(AppIcons.arrowBack),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              _CourseBanner(title: course.title, subtitle: course.subtitle),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Designado por Santa Maria',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.successDarkGreen)),
                    const SizedBox(height: 10),
                    Text(module.description,
                        style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.55,
                            color: AppColors.textMuted)),
                    const SectionHeader('Conteúdos'),
                    for (final l in module.lessons) _LessonRow(lesson: l),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: PrimaryButton('Continuar modulo 1', onPressed: () {}),
          ),
          Positioned(
            right: 16,
            bottom: 88,
            child: FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () {},
              child: const SvgIcon(AppIcons.compose, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  const _CourseBanner({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2E7CA8), Color(0xFF0A4F74)],        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(subtitle.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy)),
                  ),
                  const SizedBox(height: 10),
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final Lesson lesson;
  const _LessonRow({required this.lesson});

  String get _icon => switch (lesson.kind) {
        CourseKind.video => AppIcons.play,
        CourseKind.quiz => AppIcons.quiz,
        CourseKind.audio => AppIcons.headphones,
        CourseKind.pdf => AppIcons.pdf,
        _ => AppIcons.checkCircle,
      };

  @override
  Widget build(BuildContext context) {
    final locked = lesson.status == ContentStatus.locked;
    final inProgress = lesson.status == ContentStatus.inProgress;
    final bg = inProgress
        ? AppColors.successBg
        : locked
            ? AppColors.chipBg
            : AppColors.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: inProgress ? AppColors.successDarkGreen : AppColors.border),
      ),
      child: Row(
        children: [
          SvgIcon(_icon,
              size: 22,
              color: locked ? AppColors.textMuted : AppColors.successDarkGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: locked
                            ? AppColors.textMuted
                            : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(lesson.subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
                if (lesson.detail != null)
                  Text(lesson.detail!,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (locked)
            const SvgIcon(AppIcons.lock, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Progress
class EmployeeProgressScreen extends StatelessWidget {
  const EmployeeProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Meu progresso'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Acompanhe as atividades concluídas, a duração do estudo e os marcos do treinamento.',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: AppCard(
                  child: Column(
                    children: [
                      DonutChart(0.25, color: AppColors.primary),
                      SizedBox(height: 8),
                      Text('Taxa de conclusão',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SvgIcon(AppIcons.clock, color: AppColors.primary),
                      SizedBox(height: 8),
                      Text('8.5 hrs',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text('Tempo total de estudo',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SectionHeader('Atualmente em andamento'),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SEGURANÇA NO TRABALHO',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: ProgressBar(0.75, color: AppColors.successDarkGreen)),
                    SizedBox(width: 10),
                    Text('75%',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successDarkGreen)),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Concluído com certificado'),
          const AppCard(
            child: Row(
              children: [
                SvgIcon(AppIcons.award,
                    size: 30, color: AppColors.successDarkGreen),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NOME DO CURSO',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Completed on Jan 10 • Certificate Earned',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                SvgIcon(AppIcons.download, size: 22, color: AppColors.primary),
              ],
            ),
          ),
          const SectionHeader('Frequência Semanal aos Estudos'),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    for (final d in MockData.weeklyStudy) ...[
                      Expanded(child: Text(d.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted))),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final d in MockData.weeklyStudy) ...[
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: d.value >= 0.8
                                  ? AppColors.primary
                                  : AppColors.chipBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Rewards
class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Recompensas e Certificados'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Level card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF0D9488), AppColors.primary],
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NÍVEL ATUAL',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                              letterSpacing: 0.6)),
                      SizedBox(height: 4),
                      Text('nível 3',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      SizedBox(height: 2),
                      Text('800 pontos para o próximo nível',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.white)),
                    ],
                  ),
                ),
                Column(
                  children: const [
                    Text('1,250',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text('Pontos',
                        style: TextStyle(
                            fontSize: 13, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Seus certificados conquistados'),
          AppCard(
            child: Column(
              children: [
                for (final c in MockData.certificates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SvgIcon(AppIcons.award,
                            size: 30, color: AppColors.successDarkGreen),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.courseName,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                              Text('${c.earnedAt} • ID: ${c.code}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        const SvgIcon(AppIcons.download,
                            size: 22, color: AppColors.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader('Resgatar item'),
          Row(
            children: [
              for (final r in MockData.rewards.take(2)) ...[
                Expanded(child: _RewardTile(reward: r)),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final r in MockData.rewards.skip(2).take(2)) ...[
                Expanded(child: _RewardTile(reward: r)),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SectionHeader('Ranking da Empresa (Top 3)'),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < MockData.ranking.length; i++)
                  _RankingRow(rank: i + 1, entry: MockData.ranking[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  final Reward reward;
  const _RewardTile({required this.reward});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 82,
            width: double.infinity,
            decoration: BoxDecoration(
              color: reward.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SvgIcon(reward.icon, size: 34, color: reward.color),
          ),
          const SizedBox(height: 8),
          // Fixed 2-line title box keeps all tiles in a row the same height
          // and the price aligned, regardless of title wrapping.
          SizedBox(
            height: 40,
            child: Text(
              reward.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25),
            ),
          ),
          Text('${reward.points} Points',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successDarkGreen)),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int rank;
  final RankingEntry entry;

  const _RankingRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final highlight = rank == 2;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.successBg : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: highlight ? AppColors.successDarkGreen : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank.',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text('${entry.name} (${entry.department})',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: highlight ? AppColors.successDarkGreen : AppColors.textPrimary)),
          ),
          Text('${entry.points} pts',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: highlight ? AppColors.successDarkGreen : AppColors.primary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Profile
class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: AvatarBadge('JS', size: 84)),
          const SizedBox(height: 12),
          const Center(
              child: Text('João Silva',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(height: 4),
          const Center(
              child: Text('Departamento de Operações',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Grupo Santa Maria',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successDarkGreen)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: _ProfileStat(value: '3', label: 'Completo')),
              Expanded(child: _ProfileStat(value: '1', label: 'Certificado')),
              Expanded(
                  child: _ProfileStat(value: '1,250', label: 'Ponto')),
            ],
          ),
          const SizedBox(height: 8),
          const Text('ACCOUNT SETTINGS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          const _SettingsRow(
            icon: AppIcons.bell,
            label: 'Notificações',
            trailing: 'Enabled',
          ),
          const _SettingsRow(
            icon: AppIcons.globe,
            label: 'App Language',
            trailing: 'English',
          ),
          const _DarkModeRow(),
          const _SettingsRow(
            icon: AppIcons.help,
            label: 'Suporte e Ajuda',
            trailing: null,
            chevron: true,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              ref.read(sessionProvider.notifier).logout();
              context.go('/welcome');
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: AppColors.danger),
              foregroundColor: AppColors.danger,
              backgroundColor: AppColors.dangerBg,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(AppIcons.logout, size: 18),
                SizedBox(width: 8),
                Text('Log Out',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 12.5, color: AppColors.textMuted)),
      ],
    );
  }
}

class _DarkModeRow extends StatefulWidget {
  const _DarkModeRow();

  @override
  State<_DarkModeRow> createState() => _DarkModeRowState();
}

class _DarkModeRowState extends State<_DarkModeRow> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowShell(
      icon: AppIcons.moon,
      label: 'Dark Mode',
      trailing: Switch(
        value: _dark,
        activeThumbColor: AppColors.successDarkGreen,
        onChanged: (v) => setState(() => _dark = v),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String icon;
  final String label;
  final String? trailing;
  final bool chevron;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRowShell(
      icon: icon,
      label: label,
      trailing: trailing != null
          ? Text(trailing!,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successDarkGreen))
          : (chevron
              ? const SvgIcon(AppIcons.chevronRight,
                  color: AppColors.textMuted)
              : null),
    );
  }
}

class _SettingsRowShell extends StatelessWidget {
  final String icon;
  final String label;
  final Widget? trailing;

  const _SettingsRowShell({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SvgIcon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600))),
          ?trailing,
        ],
      ),
    );
  }
}
