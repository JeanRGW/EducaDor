import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/employee_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../app/theme.dart';
import '../gestor/widgets.dart' show DataSkeleton, DataErrorCard;
import 'widgets.dart';

class ModulesScreen extends ConsumerWidget {
  const ModulesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(employeeScopeProvider);
    return _Catalog(key: ValueKey(scope), scope: scope);
  }
}

class _Catalog extends ConsumerStatefulWidget {
  final EmployeeScope scope;
  const _Catalog({super.key, required this.scope});
  @override
  ConsumerState<_Catalog> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<_Catalog> {
  String _search = '';
  int _filter = 0, _tab = 0, _offset = 0;
  Timer? _debounce;
  static const _kinds = [null, 'video', 'audio', 'quiz', 'reading', 'pdf'];
  LearningQuery _query(int offset) => (
    scope: widget.scope,
    search: _search,
    kind: _kinds[_filter],
    state: _tab == 0 ? null : 'not_started',
    offset: offset,
  );
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(learningCatalogProvider(_query(offset))),
    ];
    final items = [for (final page in pages) ...?page.asData?.value.items];
    final total = pages.first.asData?.value.total;
    final stackedHeader = MediaQuery.textScalerOf(context).scale(12) > 17;
    return Theme(
      data: EmployeeStyles.theme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: stackedHeader ? 104 : 56,
          shape: const Border(),
          title: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = stackedHeader;
              final title = Text(
                'MÓDULOS',
                style: AdminStyles.pageTitle.copyWith(
                  fontSize: constraints.maxWidth < 340 ? 18 : 20,
                ),
              );
              final tabs = Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, label) in [
                      (0, 'Meu aprendizado'),
                      (1, 'Descobrir'),
                    ])
                      Semantics(
                        selected: _tab == index,
                        child: Material(
                          color: _tab == index
                              ? AppColors.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => setState(() {
                              _tab = index;
                              _offset = 0;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              child: Text(
                                label,
                                style: AdminStyles.fieldLabel.copyWith(
                                  fontFamily: AppFonts.outfit,
                                  fontWeight: FontWeight.w700,
                                  fontSize: constraints.maxWidth < 340
                                      ? 10
                                      : 11,
                                  color: _tab == index
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: tabs,
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [title, const SizedBox(width: 8), tabs],
              );
            },
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(learningCatalogProvider);
            setState(() => _offset = 0);
            try {
              await ref.read(learningCatalogProvider(_query(0)).future);
            } catch (_) {}
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SearchField(
                        'Pesquisar conteúdo de aprendizagem...',
                        compact: true,
                        prefixIcon: const SvgIcon(
                          AppIcons.search,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (mounted) {
                                setState(() {
                                  _search = value.trim();
                                  _offset = 0;
                                });
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      FilterChips(
                        options: const [
                          'Todos',
                          'Vídeos',
                          'Áudios',
                          'Quizzes',
                          'Leitura',
                          'PDFs',
                        ],
                        selected: _filter,
                        outlined: true,
                        solidSelection: true,
                        activeColor: AppColors.primary,
                        onSelected: (index) => setState(() {
                          _filter = index;
                          _offset = 0;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        if (pages[i].hasError)
                          DataErrorCard(
                            message: 'Não foi possível carregar cursos.',
                            retry: () => ref.invalidate(
                              learningCatalogProvider(_query(i * 50)),
                            ),
                          ),
                      if (pages.first.isLoading) const DataSkeleton(),
                      if (total == 0)
                        const AppCard(
                          child: Text(
                            'Nenhum curso disponível para esta pesquisa.',
                            style: AdminStyles.body,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LearningCard(course: items[index]),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_offset > 0 && pages.last.isLoading)
                        const DataSkeleton(),
                      if (total != null &&
                          items.length < total &&
                          pages.last.asData?.value.items.length == 50)
                        TextButton(
                          onPressed: () => setState(() => _offset += 50),
                          child: const Text('Carregar mais cursos'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
