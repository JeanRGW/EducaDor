import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/repositories/company_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';

class ContentCatalogScreen extends ConsumerStatefulWidget {
  final bool platform;
  const ContentCatalogScreen({super.key, required this.platform});

  @override
  ConsumerState<ContentCatalogScreen> createState() =>
      _ContentCatalogScreenState();
}

class _ContentCatalogScreenState extends ConsumerState<ContentCatalogScreen> {
  List<ManagedContent>? _items;
  bool _loading = false;
  bool _error = false;
  bool _more = false;
  int _chip = 0;
  int _request = 0;
  String _search = '';
  Timer? _debounce;
  final Set<String> _busy = {};
  static const _kinds = [null, 'course', 'module', 'quiz'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    final offset = append ? _items!.length : 0;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await ref
          .read(contentRepositoryProvider)
          .catalog(search: _search, kind: _kinds[_chip], offset: offset);
      if (!mounted || request != _request) return;
      setState(() {
        _items = [if (append) ..._items!, ...rows];
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _change(
    ManagedContent item,
    Future<void> Function() write,
  ) async {
    setState(() => _busy.add(item.id));
    try {
      await write();
      if (widget.platform) {
        ref.invalidate(gestorDashboardProvider);
        ref.invalidate(gestorCompletionProvider);
      } else {
        ref.invalidate(companyDashboardProvider);
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível atualizar o acesso. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      backgroundColor: widget.platform ? AppColors.surface : null,
      titleTextStyle: widget.platform
          ? const TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.2,
            )
          : null,
      title: const Text('Conteúdo Educacional'),
    ),
    floatingActionButton: widget.platform
        ? FloatingActionButton(
            tooltip: 'Adicionar trilha',
            backgroundColor: AppColors.successDarkGreen,
            shape: const CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            onPressed: () async {
              await context.push('/gestor/trail/add');
              if (mounted) {
                ref.invalidate(gestorDashboardProvider);
                ref.invalidate(gestorCompletionProvider);
                _load();
              }
            },
            child: const SvgIcon(AppIcons.compose, color: Colors.white),
          )
        : null,
    body: RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                SearchField(
                  'Pesquisar cursos, módulos...',
                  compact: true,
                  prefixIcon: SvgIcon(
                    AppIcons.search,
                    size: widget.platform ? 26 : 18,
                    color: const Color(0xFF475569),
                  ),
                  onChanged: (value) {
                    _search = value;
                    _request++;
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _load(),
                    );
                  },
                ),
                const SizedBox(height: 14),
                FilterChips(
                  plainInactive: widget.platform,
                  outlined: !widget.platform,
                  options: const ['Todos', 'Cursos', 'Módulos', 'Quizzes'],
                  selected: _chip,
                  onSelected: (index) {
                    _debounce?.cancel();
                    setState(() => _chip = index);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(
                child: Column(
                  children: [
                    const Text('Não foi possível carregar o conteúdo.'),
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          if (_items == null && !_error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CatalogSkeleton(platform: widget.platform),
            ),
          if (_items?.isEmpty == true && !_error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(
                child: Text(
                  _search.isNotEmpty || _chip != 0
                      ? 'Nenhum conteúdo encontrado.'
                      : widget.platform
                      ? 'Nenhuma trilha publicada. Adicione a primeira trilha.'
                      : 'Nenhum conteúdo liberado para esta empresa.',
                ),
              ),
            ),
          for (final item in _items ?? <ManagedContent>[])
            Padding(
              key: ValueKey(item.id),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ManagedContentCard(
                item: item,
                platform: widget.platform,
                busy: _busy.contains(item.id) || _loading,
                onToggle: (enabled) => _change(item, () {
                  final repo = ref.read(contentRepositoryProvider);
                  return widget.platform
                      ? repo.setPlatformEnabled(item.id, enabled)
                      : repo.setCompanyEnabled(item.id, enabled);
                }),
                onDetails: widget.platform
                    ? () async {
                        await context.push('/gestor/course/${item.id}');
                        if (mounted) await _load();
                      }
                    : null,
              ),
            ),
          if (_more)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: _loading ? null : () => _load(append: true),
                child: Text(
                  _loading ? 'Carregando...' : 'Carregar mais conteúdo',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class ManagedContentCard extends StatelessWidget {
  final ManagedContent item;
  final bool platform;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onDetails;

  const ManagedContentCard({
    super.key,
    required this.item,
    required this.platform,
    required this.busy,
    required this.onToggle,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final available = item.platformEnabled && (platform || item.companyEnabled);
    final caption = !item.platformEnabled
        ? 'Pausado pela plataforma'
        : !platform && !item.companyEnabled
        ? 'Pausado pela empresa'
        : platform
        ? 'Acesso liberado'
        : 'Liberado para os funcionários';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 110,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.coverUrl != null)
                    Image.network(
                      item.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _CoverFallback(),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const ColoredBox(color: AppColors.chipBg),
                    )
                  else
                    const _CoverFallback(),
                  if (!available)
                    ColoredBox(
                      color: AppColors.surface.withValues(alpha: 0.45),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.kindLabel,
                        style: TextStyle(
                          fontFamily: AppFonts.inter,
                          fontSize: platform ? 10 : 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: platform
                        ? TextStyle(
                            fontFamily: AppFonts.outfit,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: available
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            height: 1.3,
                          )
                        : AdminStyles.cardTitle.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  if (platform)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '${item.lessonCount} ${item.lessonCount == 1 ? 'aula' : 'aulas'}  ·  ',
                          ),
                          TextSpan(
                            text: item.allCompanies
                                ? 'Todas as empresas'
                                : '${item.companyCount} ${item.companyCount == 1 ? 'empresa liberada' : 'empresas liberadas'}',
                            style: TextStyle(
                              color: available
                                  ? AppColors.successDarkGreen
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFamily: AppFonts.inter,
                        fontSize: 11,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    )
                  else
                    Text(
                      '${item.lessonCount} ${item.lessonCount == 1 ? 'aula' : 'aulas'}',
                      style: AdminStyles.body.copyWith(fontSize: 11),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          platform
                              ? 'Conclusão nas empresas'
                              : 'Conclusão dos funcionários',
                          style: platform
                              ? TextStyle(
                                  fontFamily: AppFonts.inter,
                                  fontSize: 11,
                                  color: available
                                      ? const Color(0xFF475569)
                                      : AppColors.textMuted,
                                  height: 1.4,
                                )
                              : AdminStyles.body.copyWith(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.completionPct == null
                            ? 'Sem dados'
                            : '${item.completionPct!.round()}%',
                        style: TextStyle(
                          fontFamily: AppFonts.inter,
                          fontSize: platform ? 11 : 12,
                          fontWeight: FontWeight.w700,
                          color: platform && !available
                              ? AppColors.textMuted
                              : platform
                              ? AppColors.textPrimary
                              : AppColors.successDarkGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProgressBar(
                    (item.completionPct ?? 0) / 100,
                    height: platform ? 4 : 6,
                    color: AppColors.successDarkGreen,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    textDirection: platform
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Expanded(
                        child: Text(
                          busy ? 'Atualizando acesso...' : caption,
                          style: TextStyle(
                            fontFamily: AppFonts.inter,
                            fontSize: platform ? 11 : 12,
                            color: available
                                ? AppColors.successDarkGreen
                                : platform
                                ? AppColors.textMuted
                                : AppColors.navy,
                          ),
                        ),
                      ),
                      Semantics(
                        label:
                            '${platform ? 'Acesso global' : 'Acesso dos funcionários'}: ${item.title}',
                        child: SizedBox(
                          width: platform ? 52 : null,
                          height: platform ? 48 : null,
                          child: Transform.scale(
                            scale: platform ? 0.55 : 1,
                            alignment: Alignment.centerLeft,
                            child: Switch(
                              value: platform
                                  ? item.platformEnabled
                                  : item.companyEnabled,
                              activeThumbColor: platform
                                  ? Colors.white
                                  : AppColors.successDarkGreen,
                              activeTrackColor: platform
                                  ? AppColors.successDarkGreen
                                  : null,
                              inactiveThumbColor: platform
                                  ? Colors.white
                                  : null,
                              inactiveTrackColor: platform
                                  ? AppColors.border
                                  : null,
                              trackOutlineColor: platform
                                  ? const WidgetStatePropertyAll(
                                      Colors.transparent,
                                    )
                                  : null,
                              onChanged:
                                  busy || (!platform && !item.platformEnabled)
                                  ? null
                                  : onToggle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (platform)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.successDarkGreen,
                          backgroundColor: AppColors.successBgSoft,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: AppFonts.inter,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: busy ? null : onDetails,
                        icon: const SvgIcon(
                          AppIcons.edit,
                          color: AppColors.successDarkGreen,
                          size: 16,
                        ),
                        label: const Text('Editar'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.successBgSoft,
    child: Center(
      child: SvgIcon(
        AppIcons.book,
        size: 44,
        color: AppColors.successDarkGreen,
      ),
    ),
  );
}

class _CatalogSkeleton extends StatelessWidget {
  final bool platform;
  const _CatalogSkeleton({required this.platform});
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          height: 110,
          width: double.infinity,
          child: ColoredBox(color: AppColors.chipBg),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final (height, gap)
                  in platform
                      ? [
                          (18.0, 4.0),
                          (16.0, 14.0),
                          (16.0, 8.0),
                          (4.0, 8.0),
                          (48.0, 0.0),
                          (40.0, 0.0),
                        ]
                      : [
                          (20.0, 8.0),
                          (16.0, 8.0),
                          (14.0, 8.0),
                          (6.0, 8.0),
                          (48.0, 8.0),
                        ]) ...[
                SizedBox(
                  height: height,
                  width: double.infinity,
                  child: const ColoredBox(color: AppColors.chipBg),
                ),
                SizedBox(height: gap),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
