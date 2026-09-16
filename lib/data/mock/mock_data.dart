import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/app_icons.dart';
import '../models/models.dart';

/// Static seed data mirroring the Figma mockups.
class MockData {
  MockData._();

  // ---- Users (auth) ----
  static const gestor = User(
    id: 'u-gestor',
    fullName: 'Nome Gestor',
    email: 'gestor@educador.com',
    initials: 'AM',
    role: Role.gestor,
  );

  static const empresaUser = User(
    id: 'u-empresa',
    fullName: 'Grupo Santa Maria',
    email: 'empresa@educador.com',
    initials: 'GS',
    role: Role.empresa,
  );

  static const funcionarioUser = User(
    id: 'u-joao',
    fullName: 'João Silva',
    email: 'joao.silva@santamaria.com',
    initials: 'JS',
    role: Role.funcionario,
    department: 'Departamento de Operações',
    jobTitle: 'Auxiliar de Operações',
    companyId: 'c-santa-maria',
  );

  // ---- Companies ----
  static const companies = <Company>[
    Company(
      id: 'c-santa-maria',
      name: 'Grupo Santa Maria',
      cnpj: '12.345.678/0001-90',
      responsibleName: 'Elen Guimarães',
      email: 'admin@santamaria.com',
      phone: '(31) 99999-9999',
      address: 'Rua das Flores, 120',
      city: 'Belo Horizonte',
      state: 'MG',
      field: 'Operações',
      employeeCount: 156,
      active: true,
      registeredAt: '15 Jan 2024',
      initials: 'GS',
    ),
    Company(
      id: 'c-unimed',
      name: 'Unimed Belo Horizonte',
      cnpj: '98.765.432/0001-10',
      responsibleName: 'Elen Guimarães',
      email: 'admin@unimedbh.com',
      phone: '(31) 98888-8888',
      address: 'Av. do Contorno, 500',
      city: 'Belo Horizonte',
      state: 'MG',
      field: 'Saúde',
      employeeCount: 500,
      active: true,
      registeredAt: '08 Dec 2023',
      initials: 'UB',
    ),
    Company(
      id: 'c-oftalmo',
      name: 'Clínica Oftalmo Vale',
      cnpj: '11.222.333/0001-44',
      responsibleName: 'Dr. Júlio Campos',
      email: 'admin@oftalmovale.com',
      phone: '(31) 97777-7777',
      address: 'Rua da Saúde, 88',
      city: 'Belo Horizonte',
      state: 'MG',
      field: 'Saúde',
      employeeCount: 35,
      active: false,
      registeredAt: '24 Nov 2023',
      initials: 'CV',
    ),
  ];

  static Company companyById(String id) =>
      companies.firstWhere((c) => c.id == id, orElse: () => companies.first);

  // ---- Employees (company admin) ----
  static const employees = <Employee>[
    Employee(
      id: 'e-1',
      fullName: 'Roberto Silva',
      initials: 'RS',
      email: 'roberto@empresa.com',
      department: 'RH',
      jobTitle: 'Analista de RH',
      phone: '(31) 98881-1111',
      birthDate: '12/05/1990',
      address: 'Rua A, 90',
      status: EmployeeStatus.active,
      completionPct: 85,
      lastActivity: 'Ativo agora',
    ),
    Employee(
      id: 'e-2',
      fullName: 'Patrícia Menezes',
      initials: 'PM',
      email: 'patricia@empresa.com',
      department: 'Administration',
      jobTitle: 'Assistente Administrativo',
      phone: '(31) 98882-2222',
      birthDate: '03/11/1988',
      address: 'Rua B, 120',
      status: EmployeeStatus.onLeave,
      completionPct: 40,
      lastActivity: 'há 10 dias',
    ),
    Employee(
      id: 'e-3',
      fullName: 'Marcelo Hadas',
      initials: 'MH',
      email: 'marcelo@empresa.com',
      department: 'Estruturas / Obras',
      jobTitle: 'Encarregado de Obras',
      phone: '(31) 99882-1212',
      birthDate: '01/02/2026',
      address: 'Rua C, 45',
      status: EmployeeStatus.active,
      completionPct: 95,
      lastActivity: 'Ativo agora',
    ),
    Employee(
      id: 'e-4',
      fullName: 'Lucas Melo',
      initials: 'LM',
      email: 'lucas@empresa.com',
      department: 'Acabamentos',
      jobTitle: 'Líder de Equipe',
      phone: '(31) 98883-3333',
      birthDate: '22/07/1992',
      address: 'Rua D, 32',
      status: EmployeeStatus.active,
      completionPct: 98,
      lastActivity: 'Pegou recompensa vale café',
    ),
    Employee(
      id: 'e-5',
      fullName: 'Clara Batista',
      initials: 'CC',
      email: 'clara@empresa.com',
      department: 'Limpeza',
      jobTitle: 'Auxiliar de Limpeza',
      phone: '(31) 98884-4444',
      birthDate: '18/01/1995',
      address: 'Rua E, 17',
      status: EmployeeStatus.active,
      completionPct: 100,
      lastActivity: 'Terminou o módulo 3',
    ),
  ];

  // ---- Courses (modulos/cursos for employee + content for gestor) ----
  static const courses = <Course>[
    Course(
      id: 'crs-seg',
      title: 'Segurança no trabalho',
      kindLabel: 'Curso',
      kind: CourseKind.course,
      coverColor: '#0A87C7',
      subtitle: 'Modulo 1',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 75,
      meta: '12 horas • Liberado para 32 empresas',
    ),
    Course(
      id: 'crs-ergo',
      title: 'Ergonomia',
      kindLabel: 'curso',
      kind: CourseKind.course,
      coverColor: '#2BB7A8',
      subtitle: 'Modulo 2',
      statusLabel: 'Bloqueado',
      status: ContentStatus.locked,
      progress: 100,
      meta: 'Video',
    ),
    Course(
      id: 'crs-saude',
      title: 'Saúde',
      kindLabel: 'Curso',
      kind: CourseKind.video,
      coverColor: '#7FC3E8',
      subtitle: 'Modulo 3',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 75,
      meta: 'Video • 5 min restantes',
    ),
    Course(
      id: 'crs-socorro',
      title: 'Primeiros Socorros e RCP',
      kindLabel: 'Curso',
      kind: CourseKind.course,
      coverColor: '#0E7C86',
      subtitle: 'Modulo 2',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 0,
      meta: 'Video',
    ),
    Course(
      id: 'crs-tec',
      title: 'Tecnologia na Educação',
      kindLabel: 'Curso',
      kind: CourseKind.course,
      coverColor: '#0568AE',
      subtitle: 'Módulo 5',
      statusLabel: 'Liberado',
      status: ContentStatus.completed,
      progress: 100,
      meta: '840 conclusões • +12% de interesse',
    ),
    Course(
      id: 'crs-mental',
      title: 'Saúde mental',
      kindLabel: 'Módulo',
      kind: CourseKind.module,
      coverColor: '#1565A0',
      subtitle: 'Módulo 4',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 45,
      meta: '620 conclusões • +8% de interesse',
    ),
  ];

  static Course courseById(String id) =>
      courses.firstWhere((c) => c.id == id, orElse: () => courses.first);

  // ---- Module detail ----
  static const modules = <Module>[
    Module(
      id: 'mod-1',
      title: 'Segurança no trabalho',
      duration: '20m',
      progress: 75,
      status: ContentStatus.inProgress,
      description:
          'Aprenda os principais conceitos de segurança do trabalho, prevenção de acidentes e cuidados necessários para manter um ambiente de trabalho seguro e saudável.',
      designedBy: 'Santa Maria',
      coverColor: '#0A87C7',
      lessons: [
        Lesson(
          id: 'l1',
          title: 'Module 1: Introdução',
          subtitle: '12m',
          kind: CourseKind.reading,
          status: ContentStatus.completed,
          detail: 'Completed on Jan 14',
        ),
        Lesson(
          id: 'l2',
          title: 'Vídeo',
          subtitle: '20m',
          kind: CourseKind.video,
          status: ContentStatus.completed,
        ),
        Lesson(
          id: 'l3',
          title: 'Quiz',
          subtitle: 'In Progress (75% completed)',
          kind: CourseKind.quiz,
          status: ContentStatus.inProgress,
        ),
        Lesson(
          id: 'l4',
          title: 'Conversar com profissional',
          subtitle: 'Locked · Complete prior modules',
          kind: CourseKind.reading,
          status: ContentStatus.locked,
        ),
      ],
    ),
  ];

  static Module moduleById(String id) =>
      modules.firstWhere((m) => m.id == id, orElse: () => modules.first);

  // ---- Employee progress ----
  static const weeklyStudy = <WeeklyStudyDay>[
    WeeklyStudyDay('Mon', 0.9),
    WeeklyStudyDay('Tue', 0.85),
    WeeklyStudyDay('Wed', 0.9),
    WeeklyStudyDay('Thu', 0.9),
    WeeklyStudyDay('Fri', 0.9),
    WeeklyStudyDay('Sat', 0.5),
    WeeklyStudyDay('Sun', 0.5),
  ];

  static const certificates = <Certificate>[
    Certificate(
      id: 'cert-1',
      courseName: 'Nome do Curso',
      earnedAt: 'Jan 10, 2026',
      code: 'GSM-18302',
    ),
  ];

  static const rewards = <Reward>[
    Reward(
      id: 'r1',
      title: 'Caneta térmica',
      points: 500,
      icon: AppIcons.edit,
      color: Color(0xFF5C6B7A),
    ),
    Reward(
      id: 'r2',
      title: 'Cartão-presente de R\$…',
      points: 1200,
      icon: AppIcons.gift,
      color: Color(0xFF7A5CC4),
    ),
    Reward(
      id: 'r3',
      title: 'Vale café',
      points: 300,
      icon: AppIcons.coffee,
      color: Color(0xFFB7791F),
    ),
    Reward(
      id: 'r4',
      title: 'Headset',
      points: 900,
      icon: AppIcons.headset,
      color: AppColors.successDarkGreen,
    ),
  ];

  static const ranking = <RankingEntry>[
    RankingEntry(name: 'Ana Souza', department: 'HR', points: 2450),
    RankingEntry(name: 'João Silva', department: 'Ops', points: 1250),
    RankingEntry(name: 'Carlos Lima', department: 'Nurse', points: 1100),
  ];

  static const highlightEmployees = <Employee>[
    Employee(
      id: 'e-4',
      fullName: 'Lucas Melo',
      initials: 'LM',
      email: '',
      department: 'Acabamentos',
      jobTitle: '',
      phone: '',
      birthDate: '',
      address: '',
      status: EmployeeStatus.active,
      completionPct: 98,
      lastActivity: 'Pegou recompensa vale café',
    ),
    Employee(
      id: 'e-5',
      fullName: 'Clara Batista',
      initials: 'CC',
      email: '',
      department: 'Limpeza',
      jobTitle: '',
      phone: '',
      birthDate: '',
      address: '',
      status: EmployeeStatus.active,
      completionPct: 100,
      lastActivity: 'Terminou o módulo 3',
    ),
  ];

  // ---- Gestor dashboard stats ----
  static const gestorStats = <StatMetric>[
    StatMetric(
      label: 'Total de empresas',
      value: '47',
      delta: '+4 este mês',
      icon: AppIcons.building,
    ),
    StatMetric(
      label: 'Total de Usuário',
      value: '2,384',
      delta: '+18,2% que o semestre A.',
      icon: AppIcons.groups,
    ),
    StatMetric(
      label: 'Taxa de conclusão',
      value: '78.3%',
      delta: 'Tendência média de +2,4%',
      icon: AppIcons.checkCircle,
    ),
    StatMetric(
      label: 'Usuários ativos',
      value: '1,891',
      delta: 'Usuários ativos',
      icon: AppIcons.trendUp,
    ),
  ];

  // ---- Empresa dashboard stats ----
  static const empresaStats = <StatMetric>[
    StatMetric(
      label: 'Total de funcionários',
      value: '156',
      delta: '+12 inscritos',
      icon: AppIcons.groups,
    ),
    StatMetric(
      label: 'Cursos Ativos',
      value: '12',
      delta: 'Dentro do prazo',
      icon: AppIcons.book,
    ),
    StatMetric(
      label: 'Média de conclusão',
      value: '82.4%',
      delta: '+3,1% neste mês',
      icon: AppIcons.task,
    ),
    StatMetric(
      label: 'Certificados',
      value: '89',
      delta: 'emitidos',
      icon: AppIcons.award,
    ),
  ];

  // ---- Recent activities (gestor) ----
  static const activities = <Activity>[
    Activity(
      id: 'a1',
      icon: AppIcons.plus,
      color: AppColors.success,
      text: 'Unimed BH cadastrada como novo cliente',
      timeAgo: '10 mins ago',
    ),
    Activity(
      id: 'a2',
      icon: AppIcons.check,
      color: AppColors.success,
      text: 'A Dra. Maria concluiu o Módulo de Pediatria.',
      timeAgo: '25 mins ago',
    ),
    Activity(
      id: 'a3',
      icon: AppIcons.building,
      color: AppColors.primary,
      text: 'Empresa "Construtora Hadas" cadastrada',
      timeAgo: '2 hours ago',
    ),
  ];

  // ---- Gestor reports ----
  static const completionByCompany = <MapEntry<String, double>>[
    MapEntry('Unimed BH', 92),
    MapEntry('Santa Casa BH', 81),
    MapEntry('MedGrupo BH', 75),
    MapEntry('Santa Maria', 64),
  ];

  static const popularContent = <MapEntry<String, String>>[
    MapEntry('Tecnologia na Educação - curso', '840 conclusões • +12% de interesse'),
    MapEntry('Saúde mental - módulo', '620 conclusões • +8% de interesse'),
    MapEntry('Segurança no trabalho', '410 conclusões • +15% de interesse'),
  ];

  // ---- Empresa reports ----
  static const completionByDep = <MapEntry<String, double>>[
    MapEntry('TI', 92),
    MapEntry('SEGURANÇA', 84),
    MapEntry('RH', 60),
    MapEntry('Administração', 45),
  ];

  // ---- Empresa monthly participation (Jul -> Dec) ----
  static const monthlyParticipation = <MapEntry<String, double>>[
    MapEntry('Jul', 0.45),
    MapEntry('Aug', 0.35),
    MapEntry('Sep', 0.62),
    MapEntry('Oct', 0.75),
    MapEntry('Nov', 0.58),
    MapEntry('Dec', 0.9),
  ];

  // ---- Gestor growth (Jan -> Jun) ----
  static const growth = <MapEntry<String, double>>[
    MapEntry('Jan', 0.15),
    MapEntry('Feb', 0.28),
    MapEntry('Mar', 0.42),
    MapEntry('Apr', 0.58),
    MapEntry('May', 0.66),
    MapEntry('Jun', 0.8),
  ];

  // ---- Gestor engagement (Jan -> Dec) ----
  static const engagement = <MapEntry<String, double>>[
    MapEntry('Jan', 0.3),
    MapEntry('Feb', 0.42),
    MapEntry('Mar', 0.55),
    MapEntry('Apr', 0.48),
    MapEntry('May', 0.6),
    MapEntry('Jun', 0.68),
    MapEntry('Jul', 0.52),
    MapEntry('Aug', 0.64),
    MapEntry('Sep', 0.78),
    MapEntry('Oct', 0.7),
    MapEntry('Nov', 0.82),
    MapEntry('Dec', 0.95),
  ];

  // ---- Content management (gestor) ----
  static const gestorContent = <Course>[
    Course(
      id: 'cm-1',
      title: 'Segurança no trabalho',
      kindLabel: 'Curso',
      kind: CourseKind.course,
      coverColor: '#0A87C7',
      subtitle: '12 horas • Liberado para 32 empresas',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 84,
      meta: 'Taxa de Conclusão das empresas',
    ),
    Course(
      id: 'cm-2',
      title: 'Saúde e bem estar',
      kindLabel: 'MODULE',
      kind: CourseKind.module,
      coverColor: '#1565A0',
      subtitle: '4 horas • 18 empresas designadas',
      statusLabel: 'Bloqueado',
      status: ContentStatus.locked,
      progress: 0,
      meta: 'Taxa de Conclusão das empresas',
    ),
  ];

  static const companyContent = <Course>[
    Course(
      id: 'c-1',
      title: 'Segurança no trabalho',
      kindLabel: 'Curso',
      kind: CourseKind.course,
      coverColor: '#0A87C7',
      subtitle: '12 horas • Liberado para os Funcionários',
      statusLabel: 'Liberado',
      status: ContentStatus.inProgress,
      progress: 84,
      meta: 'Taxa de Conclusão dos funcionários',
    ),
  ];
}
