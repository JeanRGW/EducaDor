// Local-only visual harness for light/dark review. Not shipped.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:educador/app/app.dart';
import 'package:educador/app/theme_preference.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/company_providers.dart';
import 'package:educador/data/repositories/employee_providers.dart';
import 'package:educador/data/repositories/gestor_providers.dart';
import 'package:educador/data/session/session_controller.dart';

void main() {
  final params = Uri.base.queryParameters;
  final mode = params['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
  final session = _sessionFor(params['role'] ?? 'gestor');
  runApp(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FixtureSession(session)),
        themePreferenceProvider.overrideWith(() => _FixtureTheme(mode)),

        // data overrides are inlined below
        gestorDashboardProvider.overrideWith(
          (ref) async => GestorDashboard(
            companyCount: 24,
            newCompanyCount: 3,
            userCount: 1840,
            activeUserCount: 1312,
            completionPct: 0.68,
            growth: [
              for (var i = 0; i < 6; i++)
                GrowthMonth(
                  month: DateTime(2026, 6 + i),
                  companies: 12 + i * 2,
                  users: 800 + i * 160,
                ),
            ],
            activities: [
              PlatformActivity(
                id: 'a1',
                kind: 'course',
                name: 'Marina Silva',
                title: 'Atendimento ao cliente',
                occurredAt: DateTime(2026, 11, 11, 9, 30),
              ),
              PlatformActivity(
                id: 'a2',
                kind: 'company',
                name: 'Nova Logística',
                occurredAt: DateTime(2026, 11, 10, 16, 10),
              ),
              PlatformActivity(
                id: 'a3',
                kind: 'completion',
                name: 'Camila Souza',
                title: 'Segurança da informação',
                occurredAt: DateTime(2026, 11, 9, 11, 45),
              ),
            ],
          ),
        ),
        gestorCompaniesProvider.overrideWith(
          (ref, query) async =>
              CompanyPage(items: _companies, activeCount: 1, inactiveCount: 1),
        ),
        gestorCompletionProvider.overrideWith(
          (ref, offset) async => [
            const CompanyCompletion(
              companyId: 'company-a',
              company: 'Grupo Santa Maria',
              percent: 0.82,
            ),
            const CompanyCompletion(
              companyId: 'company-b',
              company: 'Nova Logística',
              percent: null,
            ),
            const CompanyCompletion(
              companyId: 'company-c',
              company: 'Varejo Central',
              percent: 0.47,
            ),
          ],
        ),
        gestorActivityReportProvider.overrideWith(
          (ref, period) async => PlatformActivityReport(
            engagement: [
              for (var i = 0; i < 6; i++)
                EngagementMonth(
                  month: DateTime(2026, 6 + i),
                  activeUsers: 400 + i * 90,
                ),
            ],
            popularContent: const [
              PopularContent(
                courseId: 'course-1',
                title: 'Atendimento ao cliente',
                kind: 'video',
                completions: 320,
              ),
              PopularContent(
                courseId: 'course-2',
                title: 'Segurança da informação',
                kind: 'pdf',
                completions: 210,
              ),
              PopularContent(
                courseId: 'course-3',
                title: 'Comunicação assertiva',
                kind: 'quiz',
                completions: 180,
              ),
            ],
          ),
        ),
        companyDashboardProvider.overrideWith(
          (ref) async => CompanyDashboard(
            employeeCount: 128,
            activeCourseCount: 9,
            certificateCount: 41,
            completionPct: 0.74,
            engagement: [
              for (var i = 0; i < 6; i++)
                EngagementMonth(
                  month: DateTime(2026, 6 + i),
                  activeUsers: 60 + i * 9,
                ),
            ],
            highlights: _employees,
          ),
        ),
        companyEmployeesProvider.overrideWith(
          (ref, query) async => EmployeePage(
            items: _employees,
            totalCount: 128,
            filteredCount: 4,
          ),
        ),
        companyDepartmentsProvider.overrideWith(
          (ref, query) async => const [
            MapEntry('Comercial', 0.82),
            MapEntry('RH', 0.74),
            MapEntry('TI', 0.61),
            MapEntry('Operações', null),
          ],
        ),
        companyIdentityProvider.overrideWith((ref) async => _companies.first),
        employeeSummaryProvider.overrideWith((ref) async => _summary),
        learningCatalogProvider.overrideWith((ref, query) async {
          final items = switch (query.state) {
            'in_progress' => [_learning[0]],
            'completed' => [_learning[3]],
            _ => _learning,
          };
          return LearningPage(items: items, total: items.length);
        }),
        employeeCertificatesProvider.overrideWith(
          (ref, query) async => LearningPage(
            items: [
              EarnedCertificate(
                id: 'cert-1',
                code: 'EDU-2026-0001',
                courseId: 'course-4',
                courseTitle: 'Ética e compliance',
                companyName: 'Grupo Santa Maria',
                employeeName: 'Marina Silva',
                issuedAt: DateTime(2026, 9, 12),
              ),
            ],
            total: 1,
          ),
        ),
        employeeRewardsProvider.overrideWith(
          (ref, query) async => const [
            RedeemableReward(id: 'r1', title: 'Vale-café', cost: 400),
            RedeemableReward(id: 'r2', title: 'Day off', cost: 1200),
            RedeemableReward(id: 'r3', title: 'Fone bluetooth', cost: 900),
          ],
        ),
        employeeRankingProvider.overrideWith(
          (ref) async => const [
            EmployeeRank(
              userId: 'u1',
              name: 'Camila Souza',
              department: 'TI',
              points: 1820,
            ),
            EmployeeRank(
              userId: 'u2',
              name: 'Marina Silva',
              department: 'Comercial',
              points: 1250,
            ),
            EmployeeRank(
              userId: 'u3',
              name: 'Diego Almeida',
              department: 'RH',
              points: 980,
            ),
          ],
        ),
      ],
      child: const EducaDorApp(),
    ),
  );
}

class _FixtureTheme extends ThemePreference {
  _FixtureTheme(this.initial);
  final ThemeMode initial;
  @override
  ThemeMode build() => initial;
}

class _FixtureSession extends SessionController {
  _FixtureSession(this.session);
  final AppSession? session;
  @override
  Future<AppSession?> build() async => session;
}

const _user = User(
  id: 'fixture-user',
  fullName: 'Marina Silva',
  email: 'marina@example.test',
  initials: 'MS',
  gender: Gender.female,
);
const _gestorContext = AccessContext(
  role: Role.gestor,
  companyName: 'Plataforma EducaDor',
);
const _companyContext = AccessContext(
  role: Role.empresa,
  companyId: 'company-a',
  companyName: 'Grupo Santa Maria',
);
const _employeeContext = AccessContext(
  role: Role.funcionario,
  companyId: 'company-a',
  companyName: 'Grupo Santa Maria',
);

AppSession? _sessionFor(String role) => switch (role) {
  'gestor' => const AppSession(
    user: _user,
    contexts: [_gestorContext],
    active: _gestorContext,
  ),
  'empresa' => const AppSession(
    user: _user,
    contexts: [_companyContext],
    active: _companyContext,
  ),
  'funcionario' => const AppSession(
    user: _user,
    contexts: [_employeeContext],
    active: _employeeContext,
  ),
  _ => null,
};

Employee _employee(int i) => Employee(
  id: 'employee-$i',
  fullName: [
    'Roberto Silva',
    'Camila Souza',
    'Diego Almeida',
    'Fernanda Lima',
  ][i % 4],
  initials: ['RS', 'CS', 'DA', 'FL'][i % 4],
  email: 'pessoa$i@example.test',
  department: ['RH', 'TI', 'Comercial', 'Operações'][i % 4],
  jobTitle: 'Analista',
  phone: '',
  birthDate: '',
  address: '',
  status: i.isEven ? EmployeeStatus.active : EmployeeStatus.unknown,
  completionPct: 40 + i * 11,
  hasCompletion: i != 3,
  lastActivity: 'há 2 dias',
  lastActivityAt: DateTime(2026, 11, 10),
);

final _employees = [for (var i = 0; i < 4; i++) _employee(i)];

final _companies = [
  const Company(
    id: 'company-a',
    name: 'Grupo Santa Maria',
    cnpj: '12.345.678/0001-90',
    responsibleName: 'Ana Silva',
    email: 'ana@example.test',
    phone: '(11) 99999-0000',
    address: 'Av. Paulista, 1000',
    city: 'São Paulo',
    state: 'SP',
    field: 'Varejo',
    employeeCount: 128,
    active: true,
    registeredAt: '2026-02-14',
    initials: 'GS',
  ),
  const Company(
    codePrefix: 'NOV',
    id: 'company-b',
    name: 'Nova Logística',
    cnpj: '98.765.432/0001-10',
    responsibleName: 'Bruno Costa',
    email: 'bruno@example.test',
    phone: '(21) 98888-1111',
    address: 'Rua das Palmeiras, 45',
    city: 'Rio de Janeiro',
    state: 'RJ',
    field: 'Logística',
    employeeCount: 64,
    active: false,
    registeredAt: '2026-05-03',
    initials: 'NL',
  ),
];

final _learning = [
  const LearningItem(
    id: 'course-1',
    title: 'Atendimento ao cliente',
    state: 'in_progress',
    description: 'Fundamentos de atendimento e comunicação.',
    lessonCount: 8,
    completedCount: 5,
  ),
  const LearningItem(
    id: 'course-2',
    title: 'Segurança da informação',
    state: 'not_started',
    description: 'Boas práticas para proteger dados.',
    lessonCount: 6,
    completedCount: 0,
  ),
  const LearningItem(
    id: 'course-3',
    title: 'Comunicação assertiva',
    state: 'not_started',
    description: 'Técnicas de feedback e escuta ativa.',
    lessonCount: 4,
    completedCount: 0,
  ),
  const LearningItem(
    id: 'course-4',
    title: 'Ética e compliance',
    state: 'completed',
    description: 'Conduta profissional no dia a dia.',
    lessonCount: 5,
    completedCount: 5,
  ),
];

final _summary = EmployeeSummary(
  courseCount: 12,
  completedCourseCount: 7,
  certificateCount: 3,
  balance: 1250,
  department: 'Comercial',
  activity: [
    for (var i = 0; i < 21; i++)
      StudyActivity(DateTime(2026, 10, 23 + i), i % 3 == 0),
  ],
);
