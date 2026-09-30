import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import 'audience_picker.dart';

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

  Future<void> _audience(ManagedContent item) async {
    final audience = await pickContentAudience(
      context,
      ContentAudience(
        allCompanies: item.allCompanies,
        companyIds: item.companyIds,
      ),
    );
    if (audience == null || !mounted) return;
    await _change(
      item,
      () => ref.read(contentRepositoryProvider).setAudience(item.id, audience),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: const Text('Conteúdo Educacional'),
    ),
    floatingActionButton: widget.platform
        ? FloatingActionButton(
            tooltip: 'Adicionar trilha',
            backgroundColor: AppColors.successDarkGreen,
            onPressed: () async {
              await context.push('/gestor/trail/add');
              if (mounted) _load();
            },
            child: const SvgIcon(AppIcons.compose, color: Colors.white),
          )
        : null,
    body: RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SearchField(
            'Pesquisar cursos, módulos...',
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
            options: const ['Todos', 'Cursos', 'Módulos', 'Quizzes'],
            selected: _chip,
            onSelected: (index) {
              _debounce?.cancel();
              setState(() => _chip = index);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_error)
            AppCard(
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
          if (_items == null && !_error) const _CatalogSkeleton(),
          if (_items?.isEmpty == true && !_error)
            AppCard(
              child: Text(
                _search.isNotEmpty || _chip != 0
                    ? 'Nenhum conteúdo encontrado.'
                    : widget.platform
                    ? 'Nenhuma trilha publicada. Adicione a primeira trilha.'
                    : 'Nenhum conteúdo liberado para esta empresa.',
              ),
            ),
          for (final item in _items ?? <ManagedContent>[]) ...[
            ManagedContentCard(
              item: item,
              platform: widget.platform,
              busy: _busy.contains(item.id) || _loading,
              onToggle: (enabled) => _change(item, () {
                final repo = ref.read(contentRepositoryProvider);
                return widget.platform
                    ? repo.setPlatformEnabled(item.id, enabled)
                    : repo.setCompanyEnabled(item.id, enabled);
              }),
              onAudience: widget.platform ? () => _audience(item) : null,
            ),
            const SizedBox(height: 12),
          ],
          if (_more)
            TextButton(
              onPressed: _loading ? null : () => _load(append: true),
              child: Text(
                _loading ? 'Carregando...' : 'Carregar mais conteúdo',
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
  final VoidCallback? onAudience;

  const ManagedContentCard({
    super.key,
    required this.item,
    required this.platform,
    required this.busy,
    required this.onToggle,
    this.onAudience,
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
                        style: const TextStyle(
                          fontSize: 11,
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.lessonCount} ${item.lessonCount == 1 ? 'aula' : 'aulas'}'
                    '${platform ? ' · ${item.allCompanies ? 'Todas as empresas' : '${item.companyCount} empresas liberadas'}' : ''}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.navy),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          platform
                              ? 'Conclusão nas empresas'
                              : 'Conclusão dos funcionários',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.navy),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.completionPct == null
                            ? 'Sem dados'
                            : '${item.completionPct!.round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProgressBar(
                    (item.completionPct ?? 0) / 100,
                    height: 6,
                    color: AppColors.successDarkGreen,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          busy ? 'Atualizando acesso...' : caption,
                          style: TextStyle(
                            fontSize: 12,
                            color: available
                                ? AppColors.successDarkGreen
                                : AppColors.navy,
                          ),
                        ),
                      ),
                      Semantics(
                        label:
                            '${platform ? 'Acesso global' : 'Acesso dos funcionários'}: ${item.title}',
                        child: Switch(
                          value: platform
                              ? item.platformEnabled
                              : item.companyEnabled,
                          activeThumbColor: AppColors.successDarkGreen,
                          onChanged:
                              busy || (!platform && !item.platformEnabled)
                              ? null
                              : onToggle,
                        ),
                      ),
                    ],
                  ),
                  if (platform)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onAudience,
                        icon: const SvgIcon(
                          AppIcons.companies,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        label: const Text('Liberar para'),
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
  const _CatalogSkeleton();
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
              for (final height in [20.0, 16.0, 14.0, 6.0, 48.0]) ...[
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
      ],
    ),
  );
}
