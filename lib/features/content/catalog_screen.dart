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
  static const _kinds = [
    null,
    'video',
    'audio',
    'pdf',
    'reading',
    'quiz',
    'animation',
  ];

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      titleTextStyle: AdminStyles.pageTitle(context),
      title: const Text('Conteúdo Educacional'),
    ),
    floatingActionButton: widget.platform
        ? FloatingActionButton(
            tooltip: 'Adicionar curso',
            backgroundColor: AppColors.primary,
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
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                SearchField(
                  'Pesquisar cursos...',
                  compact: true,
                  prefixIcon: SvgIcon(
                    AppIcons.search,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  plainInactive: true,
                  activeColor: widget.platform
                      ? context.successForeground
                      : AppColors.primary,
                  options: const [
                    'Todos',
                    'Vídeo',
                    'Áudio',
                    'PDF',
                    'Leitura',
                    'Quiz',
                    'Imagens e animações',
                  ],
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
      borderRadius: BorderRadius.circular(16),
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
                          : ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                            ),
                    )
                  else
                    const _CoverFallback(),
                  if (!available)
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.45),
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
                        color: context.successSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.kindLabel,
                        style: TextStyle(
                          fontFamily: AppFonts.inter,
                          fontSize: platform ? 10 : 11,
                          fontWeight: FontWeight.w700,
                          color: context.successForeground,
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
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outline,
                            height: 1.3,
                          )
                        : AdminStyles.cardTitle(context).copyWith(
                            color: available
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outline,
                          ),
                  ),
                  const SizedBox(height: 4),
                  if (platform)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '${item.moduleCount} ${item.moduleCount == 1 ? 'módulo' : 'módulos'}  ·  ${item.lessonCount} ${item.lessonCount == 1 ? 'aula' : 'aulas'}  ·  ',
                          ),
                          TextSpan(
                            text: item.allCompanies
                                ? 'Todas as empresas'
                                : '${item.companyCount} ${item.companyCount == 1 ? 'empresa liberada' : 'empresas liberadas'}',
                            style: TextStyle(
                              color: available
                                  ? context.successForeground
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontFamily: AppFonts.inter,
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                        height: 1.4,
                      ),
                    )
                  else
                    Text(
                      '${item.moduleCount} ${item.moduleCount == 1 ? 'módulo' : 'módulos'}  ·  ${item.lessonCount} ${item.lessonCount == 1 ? 'aula' : 'aulas'}',
                      style: AdminStyles.body(context).copyWith(fontSize: 11),
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
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : Theme.of(context).colorScheme.outline,
                                  height: 1.4,
                                )
                              : AdminStyles.body(
                                  context,
                                ).copyWith(fontSize: 11),
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
                              ? Theme.of(context).colorScheme.outline
                              : platform
                              ? Theme.of(context).colorScheme.onSurface
                              : context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProgressBar(
                    (item.completionPct ?? 0) / 100,
                    height: platform ? 4 : 6,
                    color: platform
                        ? context.successForeground
                        : context.colors.primary,
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
                                ? context.successForeground
                                : platform
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.onSurface,
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
                            // Scale the paint, not the accessible touch target.
                            transformHitTests: false,
                            scale: platform ? 0.55 : 1,
                            alignment: Alignment.centerLeft,
                            child: Switch(
                              value: platform
                                  ? item.platformEnabled
                                  : item.companyEnabled,
                              activeThumbColor: Colors.white,
                              activeTrackColor:
                                  busy || (!platform && !item.platformEnabled)
                                  ? Theme.of(context).colorScheme.outlineVariant
                                  : platform
                                  ? context.successForeground
                                  : AppColors.primary,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              trackOutlineColor: const WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
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
                          foregroundColor: context.successForeground,
                          backgroundColor: context.softSuccessSurface,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
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
                        icon: SvgIcon(
                          AppIcons.edit,
                          color: context.successForeground,
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
  Widget build(BuildContext context) => ColoredBox(
    color: context.softSuccessSurface,
    child: Center(
      child: SvgIcon(AppIcons.book, size: 44, color: context.successForeground),
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
        SizedBox(
          height: 110,
          width: double.infinity,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
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
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
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
