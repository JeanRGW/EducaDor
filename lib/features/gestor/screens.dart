import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../auth/onboarding_screens.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/common.dart';

// ---------------------------------------------------------------- Dashboard
class GestorDashboardScreen extends StatelessWidget {
  const GestorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = MockData.gestorStats;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const AvatarBadge('AM'),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Olá, Gestor',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Gerente de Plataforma',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textMuted)),
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
          _grid(stats.sublist(0, 2)),
          const SizedBox(height: 12),
          _grid(stats.sublist(2, 4)),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Expanded(
                        child: Text('Crescimento da Empresa / Usuários',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700))),
                    Text('Últimos 6 meses',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                LineChart(MockData.growth),
              ],
            ),
          ),
          const SectionHeader('Atividade recente'),
          for (final a in MockData.activities) _ActivityRow(activity: a),
        ],
      ),
    );
  }

  Widget _grid(List<StatMetric> metrics) {
    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          Expanded(
              child: StatCard(
            label: metrics[i].label,
            value: metrics[i].value,
            icon: metrics[i].icon,
            delta: metrics[i].delta,
          )),
          const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Activity activity;
  const _ActivityRow({required this.activity});

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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: SvgIcon(activity.icon, color: activity.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity.text,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(activity.timeAgo,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Companies
class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});

  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  int _chip = 0;
  final List<String> _filters = ['Todas as empresas', 'Ativas', 'Inativas'];
  late Future<List<Company>> _companies;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _companies = ref.read(companyRepositoryProvider).all();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Empresas Registradas'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        tooltip: 'Adicionar empresa',
        onPressed: () async {
          await context.push('/gestor/company/add');
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
                  const SearchField('Pesquise o nome da empresa'),
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
          FutureBuilder<List<Company>>(future: _companies,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('Não foi possível carregar empresas.')));
              }
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()));
              }
              final companies = snapshot.data!.where((company) => _chip == 0 ||
                (_chip == 1 && company.active) ||
                (_chip == 2 && !company.active)).toList();
              return SliverPadding(padding: const EdgeInsets.all(16),
                sliver: SliverList.builder(itemCount: companies.length,
                  itemBuilder: (context, i) =>
                    _CompanyCardStatic(company: companies[i])));
            }),
        ],
      ),
    );
  }
}

class _CompanyCardStatic extends StatelessWidget {
  final Company company;
  const _CompanyCardStatic({required this.company});

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: Text(company.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              StatusChip(
                company.active ? 'Ativa' : 'Inativa',
                color: company.active ? AppColors.successDarkGreen : AppColors.danger,
                bg: company.active ? AppColors.successBg : AppColors.dangerBg,
              ),
            ],
          ),
          Text('CNPJ: ${company.cnpj}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textMuted)),
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pessoa responsável',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    Text(company.responsibleName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Funcionários',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                  Row(
                    children: [
                      const SvgIcon(AppIcons.key,
                          size: 16, color: AppColors.successDarkGreen),
                      const SizedBox(width: 4),
                      Text(company.employeeCount < 0 ? '—' : '${company.employeeCount}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.successDarkGreen)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              Text('Registro: ${company.registeredAt}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textMuted)),
              const Spacer(),
              const SvgIcon(AppIcons.chevronRight, color: AppColors.textMuted),
            ],
          ),
          if (company.active) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push(
                '/gestor/company/${company.id}/manager/add',
              ),
              child: const Text('Convidar gestor da empresa'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Add company
class AddCompanyScreen extends ConsumerStatefulWidget {
  const AddCompanyScreen({super.key});

  @override
  ConsumerState<AddCompanyScreen> createState() => _AddCompanyScreenState();
}

class _AddCompanyScreenState extends ConsumerState<AddCompanyScreen> {
  final _name = TextEditingController();
  final _cnpj = TextEditingController();
  final _responsible = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _address = TextEditingController();
  final _field = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [_name, _cnpj, _responsible, _email,
      _phone, _city, _state, _address, _field]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _responsible.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Informe empresa, responsável e e-mail válidos.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final link = await ref.read(invitationRepositoryProvider).invite(
        role: Role.empresa, name: _responsible.text, email: _email.text,
        company: {
          'name': _name.text.trim(), 'cnpj': _cnpj.text.trim(),
          'responsible': _responsible.text.trim(), 'email': _email.text.trim(),
          'phone': _phone.text.trim(), 'city': _city.text.trim(),
          'state': _state.text.trim(), 'address': _address.text.trim(),
          'field': _field.text.trim(),
        },
      );
      if (!mounted) return;
      await showInviteLink(context, link);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível criar a empresa e o convite.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar empresa'),
        leading: IconButton(
          icon: const SvgIcon(AppIcons.arrowBack),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormFieldLabel(label: 'Nome da Empresa', hint: 'santa maria', controller: _name),
          FormFieldLabel(label: 'CNPJ', hint: '00.000.000/0001-00', controller: _cnpj),
          FormFieldLabel(label: 'Primeiro gestor da empresa', hint: 'Nome completo',
            controller: _responsible),
          Row(
            children: [
              Expanded(
                child: FormFieldLabel(
                    label: 'E-mail do gestor', hint: 'admin@comp.com', controller: _email),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FormFieldLabel(
                    label: 'Telefone', hint: '(31) 99999-9999', controller: _phone),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: FormFieldLabel(
                    label: 'Cidade', hint: 'Belo Horizonte', controller: _city),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FormFieldLabel(label: 'Estado', hint: 'MG', controller: _state),
              ),
            ],
          ),
          FormFieldLabel(label: 'Endereço', hint: 'Rua, número, bairro', controller: _address),
          FormFieldLabel(label: 'Área de atuação', hint: 'Saúde', controller: _field),
          const SizedBox(height: 4),
          PrimaryButton(_busy ? 'Criando...' : 'Criar empresa e convite',
            onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Content management
class ContentManagementScreen extends StatefulWidget {
  const ContentManagementScreen({super.key});

  @override
  State<ContentManagementScreen> createState() =>
      _ContentManagementScreenState();
}

class _ContentManagementScreenState extends State<ContentManagementScreen> {
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
        onPressed: () => context.push('/gestor/trail/add'),
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
          for (final c in MockData.gestorContent) _ContentCard(course: c),
        ],
      ),
    );
  }
}

class _ContentCard extends StatefulWidget {
  final Course course;
  const _ContentCard({required this.course});

  @override
  State<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<_ContentCard> {
  late bool _enabled = widget.course.progress > 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final dimmed = !_enabled;
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
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
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
                      color: c.kindLabel == 'MODULE'
                          ? AppColors.primary
                          : AppColors.successDarkGreen,
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
                            color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                ProgressBar(c.progress / 100, height: 6,
                    color: AppColors.primary),
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
      ),
    );
  }
}

// ---------------------------------------------------------------- Add trail
class AddTrailScreen extends StatefulWidget {
  const AddTrailScreen({super.key});

  @override
  State<AddTrailScreen> createState() => _AddTrailScreenState();
}

class _AddTrailScreenState extends State<AddTrailScreen> {
  int _type = 0;
  final _types = ['Vídeo', 'Áudio', 'PDF', 'Quiz'];
  final _typeIcons = [
    AppIcons.play,
    AppIcons.headphones,
    AppIcons.pdf,
    AppIcons.quiz,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Trilha'),
        leading: IconButton(
          icon: const SvgIcon(AppIcons.arrowBack),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('TIPO DE CONTEÚDO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < _types.length; i++) ...[
                Expanded(
                  child: _TypeTile(
                    label: _types[i],
                    icon: _typeIcons[i],
                    active: _type == i,
                    onTap: () => setState(() => _type = i),
                  ),
                ),
                if (i != _types.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const FormFieldLabel(label: 'Título', hint: 'Dor crônica'),
          const FormFieldLabel(
            label: 'Modulos',
            isDropdown: true,
            items: ['Modulo 1', 'Modulo 2', 'Modulo 3'],
            value: 'Modulo 1',
          ),
          const FormFieldLabel(
              label: 'Descrição', hint: 'breve descrição da trilha'),
          const FormFieldLabel(label: 'Imagem de capa', hint: ''),
          // Cover preview with corner camera button (per Figma).
          Container(
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF6EBDD6), Color(0xFF4A9CB8)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const SvgIcon(AppIcons.camera,
                        color: AppColors.textPrimary, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(
                child: FormFieldLabel(label: 'Arquivo em video', hint: 'exercicio_lombar.mp3'),
              ),
              SizedBox(width: 12),
              Expanded(
                child: FormFieldLabel(
                  label: 'Profissional Responsável',
                  isDropdown: true,
                  items: ['Marina - Fisioterapia', 'Carlos - Medicina'],
                  value: 'Marina - Fisioterapia',
                ),
              ),
            ],
          ),
          const FormFieldLabel(
            label: 'Liberar para:',
            isDropdown: true,
            items: ['Todas as empresas', 'Grupo Santa Maria'],
            value: 'Todas as empresas',
          ),
          const SizedBox(height: 4),
          PrimaryButton('Publicar', onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trilha publicada.')));
            context.pop();
          }),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final VoidCallback onTap;

  const _TypeTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? AppColors.navy : AppColors.border),
        ),
        child: Column(
          children: [
            SvgIcon(icon,
                size: 22,
                color: active ? Colors.white : AppColors.textMuted),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Reports
class GestorReportsScreen extends StatelessWidget {
  const GestorReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('Relatórios e Análises'),
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
                    child: Text('01 Jan 2024 - 31 Jan 2024',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary))),
                SvgIcon(AppIcons.chevronDown,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
          const SectionHeader('Conclusão pela Empresa'),
          AppCard(
            child: Column(
              children: [
                for (final e in MockData.completionByCompany)
                  ReportBarRow(e.key, e.value),
              ],
            ),
          ),
          const SectionHeader('Conteúdo mais popular'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                for (var i = 0; i < MockData.popularContent.length; i++)
                  _PopularRow(
                      rank: i + 1, entry: MockData.popularContent[i]),
              ],
            ),
          ),
          const SectionHeader('Engajamento mensal dos usuários'),
          AppCard(
            child: BarChart(MockData.engagement),
          ),
        ],
      ),
    );
  }
}

class _PopularRow extends StatelessWidget {
  final int rank;
  final MapEntry<String, String> entry;
  const _PopularRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text('$rank.',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(entry.value,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Profile
class GestorProfileScreen extends ConsumerWidget {
  const GestorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: AvatarBadge(session?.user.initials ?? 'AM', size: 84)),
          const SizedBox(height: 12),
          Center(
              child: Text(session?.user.fullName ?? 'Gestor',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(height: 4),
          Center(
              child: Text(session?.user.email ?? '',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
          const SizedBox(height: 10),
          const Center(
            child: StatusChip('SUPER ADMIN',
                color: AppColors.successDarkGreen, bg: AppColors.successBg),
          ),
          const SizedBox(height: 24),
          PrimaryButton('Convidar gestor da plataforma',
            onPressed: () => context.push('/gestor/manager/add')),
          const SizedBox(height: 12),
          if ((session?.contexts.length ?? 0) > 1) ...[
            OutlinedButton(onPressed: () => context.go('/contexts'),
              child: const Text('Trocar perfil')),
            const SizedBox(height: 12),
          ],
          const _GestorMenuRow(AppIcons.manageAccount, 'Configurações de Conta'),
          const _GestorMenuRow(AppIcons.bell, 'Preferências de notificação'),
          const _GestorMenuRow(AppIcons.shield, 'Segurança e MFA'),
          const _GestorMenuRow(AppIcons.settings, 'Configurações da plataforma'),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(AppIcons.logout, size: 18),
                SizedBox(width: 8),
                Text('Sair',
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

class _GestorMenuRow extends StatelessWidget {
  final String icon;
  final String label;
  const _GestorMenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SvgIcon(icon, size: 20, color: AppColors.successDarkGreen),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600))),
          const SvgIcon(AppIcons.chevronRight, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
