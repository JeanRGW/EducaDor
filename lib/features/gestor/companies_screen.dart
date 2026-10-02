import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/gestor_providers.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../auth/pending_invites.dart';
import 'widgets.dart';

class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});
  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  int _chip = 0;
  int _offset = 0;
  int _pendingRevision = 0;
  String _search = '';
  Timer? _debounce;

  CompanyQuery _query(int offset) =>
      (search: _search, active: _chip == 0 ? null : _chip == 1, offset: offset);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    for (var offset = 0; offset <= _offset; offset += 50) {
      ref.invalidate(gestorCompaniesProvider(_query(offset)));
    }
    ref.invalidate(gestorDashboardProvider);
    ref.invalidate(gestorCompletionProvider);
    setState(() {
      _offset = 0;
      _pendingRevision++;
    });
    try {
      await ref.read(gestorCompaniesProvider(_query(0)).future);
    } catch (_) {
      /* Rendered below. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(gestorCompaniesProvider(_query(offset))),
    ];
    final counts = pages.first.asData?.value;
    final companies = [for (final page in pages) ...?page.asData?.value.items];
    final last = pages.last;
    final identity = ref.watch(
      sessionProvider.select(
        (state) => (state.value?.user.id, state.value?.role),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 32,
        backgroundColor: AppColors.surface,
        titleTextStyle: const TextStyle(
          fontFamily: AppFonts.outfit,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        title: const Text('Empresas Registradas'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.successDarkGreen,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white, width: 2),
        ),
        tooltip: 'Adicionar empresa',
        onPressed: () async {
          await context.push('/gestor/company/add');
          if (mounted) await _refresh();
        },
        child: const SvgIcon(AppIcons.plus, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            SearchField(
              'Pesquise o nome da empresa',
              compact: true,
              prefixIcon: const SvgIcon(
                AppIcons.search,
                size: 26,
                color: Color(0xFF475569),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _search = value.trim();
                      _offset = 0;
                    });
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            FilterChips(
              outlined: true,
              options: [
                'Todas as empresas',
                counts == null
                    ? 'Ativas'
                    : 'Ativas (${formatCount(counts.activeCount)})',
                counts == null
                    ? 'Inativas'
                    : 'Inativas (${formatCount(counts.inactiveCount)})',
              ],
              selected: _chip,
              onSelected: (index) => setState(() {
                _chip = index;
                _offset = 0;
              }),
            ),
            const SizedBox(height: 8),
            PendingInvitesSection(
              key: ValueKey((_pendingRevision, identity)),
              role: Role.empresa,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < pages.length; i++)
              if (pages[i].hasError)
                DataErrorCard(
                  message: 'Não foi possível carregar empresas.',
                  retry: () =>
                      ref.invalidate(gestorCompaniesProvider(_query(i * 50))),
                ),
            if (pages.first.isLoading) ...[
              const DataSkeleton(),
              const SizedBox(height: 12),
              const DataSkeleton(),
            ],
            if (companies.isEmpty &&
                pages.every(
                  (page) => page.hasValue && !page.isLoading && !page.hasError,
                ))
              AppCard(
                child: Text(
                  _search.isNotEmpty || _chip != 0
                      ? 'Nenhuma empresa encontrada.'
                      : 'Nenhuma empresa cadastrada.',
                ),
              ),
            for (final company in companies) ...[
              _CompanyCard(company: company, onInviteCreated: _refresh),
              const SizedBox(height: 12),
            ],
            if (_offset > 0 && last.isLoading) const DataSkeleton(),
            if (last.asData?.value.items.length == 50)
              TextButton(
                onPressed: () => setState(() => _offset += 50),
                child: const Text('Carregar mais empresas'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final Company company;
  final Future<void> Function() onInviteCreated;
  const _CompanyCard({required this.company, required this.onInviteCreated});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                company.name,
                style: const TextStyle(
                  fontFamily: AppFonts.outfit,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: company.active
                    ? AppColors.successBg
                    : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                company.active ? 'Ativa' : 'Inativa',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: company.active
                      ? AppColors.successDarkGreen
                      : AppColors.danger,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        Text(
          'CNPJ: ${company.cnpj}',
          style: const TextStyle(
            fontFamily: AppFonts.inter,
            fontSize: 11,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
        const Divider(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pessoa responsável',
                    style: TextStyle(
                      fontFamily: AppFonts.inter,
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  Text(
                    company.responsibleName,
                    style: const TextStyle(
                      fontFamily: AppFonts.inter,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Funcionários',
                  style: TextStyle(
                    fontFamily: AppFonts.inter,
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                Row(
                  children: [
                    const SvgIcon(
                      AppIcons.key,
                      size: 14,
                      color: AppColors.successDarkGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatCount(company.employeeCount),
                      style: const TextStyle(
                        fontFamily: AppFonts.inter,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Registro: ${company.registeredAt.isEmpty ? '—' : formatDate(DateTime.parse(company.registeredAt))}',
          style: const TextStyle(
            fontFamily: AppFonts.inter,
            fontSize: 11,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButtonTheme(
          data: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.successDarkGreen,
              minimumSize: const Size(0, 44),
              side: const BorderSide(color: AppColors.border),
              textStyle: const TextStyle(
                fontFamily: AppFonts.inter,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (company.active)
                OutlinedButton(
                  onPressed: () async {
                    await context.push(
                      '/gestor/company/${company.id}/manager/add',
                    );
                    if (context.mounted) await onInviteCreated();
                  },
                  child: const Text('Convidar gestor da empresa'),
                ),
              OutlinedButton(
                onPressed: () async {
                  await context.push('/gestor/company/${company.id}');
                  if (context.mounted) await onInviteCreated();
                },
                child: const Text('Editar'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
