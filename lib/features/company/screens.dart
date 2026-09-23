import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';

// ---------------------------------------------------------------- Dashboard
class CompanyDashboardScreen extends ConsumerWidget {
  const CompanyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const backend = String.fromEnvironment('SUPABASE_URL');
    if (backend.isNotEmpty) {
      final company = ref.watch(sessionProvider).value?.active;
      final companyId = company?.companyId;
      return Scaffold(
        appBar: AppBar(title: Text(company?.companyName ?? 'Empresa'),
          automaticallyImplyLeading: false),
        body: companyId == null ? const Center(child: Text('Selecione uma empresa.'))
          : FutureBuilder<double?>(
            future: ref.read(reportRepositoryProvider).completion(companyId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Não foi possível carregar os dados da empresa.'));
              }
              if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final percent = snapshot.data;
              return ListView(padding: const EdgeInsets.all(16), children: [
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Conclusão dos treinamentos',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(percent == null ? 'Nenhuma trilha liberada' :
                      '${percent.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 28,
                        fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(height: 10),
                    ProgressBar((percent ?? 0) / 100),
                  ])),
                const SizedBox(height: 20),
                PrimaryButton('Ver funcionários',
                  onPressed: () => context.go('/empresa/funcionarios')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => context.go('/empresa/relatorios'),
                  child: const Text('Ver conclusão da empresa')),
              ]);
            }),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const AvatarBadge('GS'),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grupo Santa Maria',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Administrador da Empresa',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              icon: const SvgIcon(AppIcons.bell),
              onPressed: () {},
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                Expanded(
                    child: StatCard(
                  label: MockData.empresaStats[i].label,
                  value: MockData.empresaStats[i].value,
                  icon: MockData.empresaStats[i].icon,
                  delta: MockData.empresaStats[i].delta,
                )),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 2; i < 4; i++) ...[
                Expanded(
                    child: StatCard(
                  label: MockData.empresaStats[i].label,
                  value: MockData.empresaStats[i].value,
                  icon: MockData.empresaStats[i].icon,
                  delta: MockData.empresaStats[i].delta,
                )),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Expanded(
                        child: Text('Participação Mensal',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700))),
                    Text('Tendência de engajamento',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                LineChart(MockData.monthlyParticipation),
              ],
            ),
          ),
          const SectionHeader('Destaques'),
          for (final e in MockData.highlightEmployees) _HighlightRow(employee: e),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final Employee employee;
  const _HighlightRow({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AvatarBadge(employee.initials, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${employee.fullName} (${employee.department})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(employee.lastActivity,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          StatusChip(
            '${employee.completionPct.round()}%',
            color: AppColors.successDarkGreen,
            bg: AppColors.successBg,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Employees list
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  int _chip = 0;
  final List<String> _filters = ['Todos os funcionários', 'Ativos', 'De licença'];
  late Future<List<Employee>> _employees;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final companyId = ref.read(sessionProvider).value?.active?.companyId;
    _employees = companyId == null ? Future.value([]) :
      ref.read(employeeRepositoryProvider).all(companyId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Funcionários cadastrados'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        tooltip: 'Convidar funcionário',
        onPressed: () async {
          await context.push('/empresa/employee/add');
          if (mounted) setState(_load);
        },
        child: const SvgIcon(AppIcons.plus, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  const SearchField('Pesquise por nome, departamento...'),
                  const SizedBox(height: 14),
                  FilterChips(
                    options: _filters,
                    selected: _chip,
                    onSelected: (i) => setState(() => _chip = i),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          FutureBuilder<List<Employee>>(future: _employees,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('Não foi possível carregar funcionários.')));
              }
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()));
              }
              final employees = snapshot.data!.where((employee) => _chip == 0 ||
                (_chip == 1 && employee.status == EmployeeStatus.active) ||
                (_chip == 2 && employee.status == EmployeeStatus.onLeave)).toList();
              return SliverPadding(padding: const EdgeInsets.all(16),
                sliver: SliverList.builder(itemCount: employees.length,
                  itemBuilder: (context, i) => _EmployeeCard(employee: employees[i])));
            }),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  const _EmployeeCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final active = employee.status == EmployeeStatus.active;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarBadge(employee.initials, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.fullName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(employee.department,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              StatusChip(
                active ? 'Ativo' : 'De licença',
                color: active ? AppColors.successDarkGreen : AppColors.danger,
                bg: active ? AppColors.successBg : AppColors.dangerBg,
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              const Expanded(
                  child: Text('Progresso de Conclusão',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textMuted))),
              Text('${employee.completionPct.round()}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(employee.completionPct / 100, height: 6),
          const SizedBox(height: 12),
          Row(
            children: [
               Expanded(
                 child: Text(employee.lastActivity.isEmpty ? 'Ativo' :
                   'Última atividade: ${employee.lastActivity}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ),
              const SvgIcon(AppIcons.chevronRight, color: AppColors.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Company content
class CompanyContentScreen extends StatefulWidget {
  const CompanyContentScreen({super.key});

  @override
  State<CompanyContentScreen> createState() => _CompanyContentScreenState();
}

class _CompanyContentScreenState extends State<CompanyContentScreen> {
  int _chip = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Conteúdo Educacional'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {},
        child: const SvgIcon(AppIcons.compose, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SearchField('Pesquisar cursos médicos, módulos...'),
          const SizedBox(height: 14),
          FilterChips(
            options: const ['Todos', 'Cursos', 'Modulos', 'Quizzes'],
            selected: _chip,
            onSelected: (i) => setState(() => _chip = i),
          ),
          const SizedBox(height: 8),
          for (final c in MockData.companyContent) _CompanyContentCard(course: c),
        ],
      ),
    );
  }
}

class _CompanyContentCard extends StatefulWidget {
  final Course course;
  const _CompanyContentCard({required this.course});

  @override
  State<_CompanyContentCard> createState() => _CompanyContentCardState();
}

class _CompanyContentCardState extends State<_CompanyContentCard> {
  bool _enabled = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 108,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              gradient: LinearGradient(
                colors: [
                  colorFromHex(c.coverColor),
                  colorFromHex(c.coverColor).withValues(alpha: 0.6),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successDarkGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(c.kindLabel,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(c.subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text(c.meta,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textMuted))),
                    Text('${c.progress.round()}%',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successDarkGreen)),
                  ],
                ),
                const SizedBox(height: 8),
                ProgressBar(c.progress / 100, height: 6,
                    color: AppColors.successDarkGreen),
                const SizedBox(height: 12),
                Switch(
                  value: _enabled,
                  activeThumbColor: AppColors.successDarkGreen,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Reports
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Relatórios'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const SvgIcon(AppIcons.download, color: AppColors.primary),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                SvgIcon(AppIcons.calendar, size: 16, color: AppColors.textMuted),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Período: Últimos 30 dias (jan. de 2026)',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary))),
                SvgIcon(AppIcons.chevronDown,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
          const SectionHeader('Conclusão por departamento'),
          AppCard(
            child: Column(
              children: [
                for (final e in MockData.completionByDep)
                  ReportBarRow(e.key, e.value),
              ],
            ),
          ),
          const SectionHeader('Indicadores Regulatórios'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _RegIndicator(
                  title: 'Funcionários com Desempenho Insuficiente (Trilha PALS)',
                  value: '4',
                  highlight: true,
                ),
                Divider(height: 22),
                _RegIndicator(
                  title: 'Certificados aguardando renovação',
                  value: '12',
                  highlight: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Exportar relatório em PDF',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton('Exportar dados em CSV',
                    onPressed: () {}, color: AppColors.primaryDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegIndicator extends StatelessWidget {
  final String title;
  final String value;
  final bool highlight;
  const _RegIndicator(
      {required this.title, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.successBgSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: highlight
                        ? AppColors.successDarkGreen
                        : AppColors.textPrimary)),
          ),
          const SizedBox(width: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Profile
class CompanyProfileScreen extends ConsumerWidget {
  const CompanyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: AvatarBadge(session?.user.initials ?? 'GS', size: 84)),
          const SizedBox(height: 12),
          Center(
              child: Text(session?.active?.companyName ?? 'Empresa',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(height: 4),
          Center(
              child: Text(const String.fromEnvironment('SUPABASE_URL').isEmpty
                  ? 'CNPJ: 12.345.678/0001-90' : session?.user.email ?? '',
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
               child: Text(const String.fromEnvironment('SUPABASE_URL').isEmpty
                   ? '300 Funcionários' : 'Gestor da empresa',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successDarkGreen)),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton('Convidar gestor da empresa',
            onPressed: () => context.push('/empresa/manager/add')),
          const SizedBox(height: 12),
          if ((session?.contexts.length ?? 0) > 1) ...[
            OutlinedButton(onPressed: () => context.go('/contexts'),
              child: const Text('Trocar perfil')),
            const SizedBox(height: 12),
          ],
          const _MenuRow('Notificações'),
          const _MenuRow('Lembretes automáticos de treinamento'),
          const _MenuRow('Gerenciar Departamento'),
          const _MenuRow('Configurações'),
          const _MenuRow('Suporte', subtitle: '24/7 dedicated admin line'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/welcome');
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
              children: [
                Expanded(
                  child: Text('Sair',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                SvgIcon(AppIcons.logout, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  const _MenuRow(this.label, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SvgIcon(AppIcons.chevronRight, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
