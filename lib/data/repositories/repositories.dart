import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../mock/mock_data.dart';
import '../models/models.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

SupabaseClient? get _client =>
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty
    ? Supabase.instance.client
    : null;

String? _publicCoverUrl(String? key) => key == null
    ? null
    : '$_supabaseUrl/storage/v1/object/public/educador-public/'
          '${key.split('/').map(Uri.encodeComponent).join('/')}';

class CompanyRepository {
  final SupabaseClient? _injectedClient;
  CompanyRepository({SupabaseClient? client}) : _injectedClient = client;

  Company _company(Map<String, dynamic> row) => Company(
    id: row['id'] as String,
    name: row['name'] as String,
    cnpj: row['cnpj'] as String? ?? '',
    responsibleName: row['responsible'] as String? ?? '',
    email: row['email'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    address: row['address'] as String? ?? '',
    city: row['city'] as String? ?? '',
    state: row['state'] as String? ?? '',
    field: row['field'] as String? ?? '',
    employeeCount: (row['employee_count'] as num?)?.toInt() ?? -1,
    active: row['active'] as bool,
    registeredAt: (row['created_at'] as String?)?.split('T').first ?? '',
    initials: (row['name'] as String)
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase(),
  );

  Future<CompanyPage> page({
    String search = '',
    bool? active,
    int offset = 0,
  }) async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar empresas.'));
    final data =
        await client.rpc(
              'gestor_companies',
              params: {
                'p_search': search.trim(),
                'p_active': active,
                'p_offset': offset,
              },
            )
            as Map<String, dynamic>;
    return CompanyPage(
      items: (data['items'] as List<dynamic>)
          .map((row) => _company(row as Map<String, dynamic>))
          .toList(),
      activeCount: (data['active_count'] as num).toInt(),
      inactiveCount: (data['inactive_count'] as num).toInt(),
    );
  }

  Future<List<CompanyOption>> options({
    int offset = 0,
    String search = '',
  }) async {
    final client = _client;
    if (client == null) return [];
    var query = client.from('companies').select('id,name,active');
    if (search.trim().isNotEmpty) {
      final escaped = search
          .trim()
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      query = query.ilike('name', '%$escaped%');
    }
    final rows = await query
        .order('name')
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (row) => CompanyOption(
            id: row['id'] as String,
            name: row['name'] as String,
            active: row['active'] as bool,
          ),
        )
        .toList();
  }

  Future<List<Company>> all() async {
    final client = _client;
    if (client == null) return MockData.companies;
    final rows = await client
        .from('companies')
        .select()
        .order('name')
        .range(0, 49);
    return rows
        .map(
          (row) => Company(
            id: row['id'] as String,
            name: row['name'] as String,
            cnpj: row['cnpj'] as String? ?? '',
            responsibleName: row['responsible'] as String? ?? '',
            email: row['email'] as String? ?? '',
            phone: row['phone'] as String? ?? '',
            address: row['address'] as String? ?? '',
            city: row['city'] as String? ?? '',
            state: row['state'] as String? ?? '',
            field: row['field'] as String? ?? '',
            employeeCount: -1,
            active: row['active'] as bool? ?? true,
            registeredAt:
                (row['created_at'] as String?)?.split('T').first ?? '',
            initials: (row['name'] as String).substring(0, 1).toUpperCase(),
          ),
        )
        .toList();
  }

  Future<Company> byId(String id) async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar empresas.'));
    final row = await client.from('companies').select().eq('id', id).single();
    return _company(row);
  }

  Future<void> update(String id, Map<String, String> fields) async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar empresas.'));
    try {
      await client.rpc(
        'update_company',
        params: {'p_company': id, 'p_fields': fields},
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const ManagementException(
          'Este CNPJ já está cadastrado em outra empresa.',
        );
      }
      rethrow;
    }
  }

  Future<void> setActive(String id, bool active) async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar empresas.'));
    await client.rpc(
      'set_company_active',
      params: {'p_company': id, 'p_active': active},
    );
  }
}

class EmployeeRepository {
  final SupabaseClient? _injectedClient;
  EmployeeRepository({SupabaseClient? client}) : _injectedClient = client;

  Future<List<Employee>> all(String companyId) async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar funcionários.'));
    final rows =
        await client.rpc(
              'employee_completion',
              params: {'p_company': companyId},
            )
            as List<dynamic>;
    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      final name = row['full_name'] as String;
      return Employee(
        id: row['user_id'] as String,
        fullName: name,
        initials: name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join(),
        email: row['email'] as String,
        department: row['dept'] as String? ?? '',
        jobTitle: row['job_title'] as String? ?? '',
        phone: '',
        birthDate: '',
        address: '',
        status: EmployeeStatus.active,
        completionPct: (row['pct'] as num?)?.toDouble() ?? 0,
        hasCompletion: row['pct'] != null,
        lastActivity: '',
      );
    }).toList();
  }
}

class PeopleRepository {
  final SupabaseClient? _injectedClient;
  PeopleRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get _peopleClient =>
      _injectedClient ??
      _client ??
      (throw StateError('Configure o Supabase para gerenciar gestores.'));

  Future<List<User>> managers({
    String? companyId,
    String search = '',
    int offset = 0,
  }) async {
    final rows =
        await _peopleClient.rpc(
              'gestor_managers',
              params: {
                'p_company': companyId,
                'p_search': search.trim(),
                'p_offset': offset,
              },
            )
            as List<dynamic>;
    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      final name = row['full_name'] as String;
      return User(
        id: row['id'] as String,
        fullName: name,
        email: row['email'] as String,
        initials: name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0])
            .join()
            .toUpperCase(),
      );
    }).toList();
  }

  Future<void> revokeAccess(String userId, {String? companyId}) async {
    try {
      await _peopleClient.rpc(
        'revoke_gestor_access',
        params: {'p_user': userId, 'p_company': companyId},
      );
    } on PostgrestException catch (error) {
      final message = switch (error.message) {
        'Last platform gestor' =>
          'A plataforma precisa manter pelo menos um gestor.',
        'Last company gestor' =>
          'A empresa precisa manter pelo menos um gestor.',
        'Access unavailable' =>
          'Este acesso já foi removido. Atualize a lista.',
        _ => null,
      };
      if (message != null) throw ManagementException(message);
      rethrow;
    }
  }

  Future<List<ProfessionalOption>> platformProfessionals({
    String search = '',
  }) async {
    final client = _client;
    if (client == null) return [];
    final grants = await client
        .from('platform_gestors')
        .select('user_id')
        .range(0, 99);
    final ids = grants.map((row) => row['user_id'] as String).toList();
    if (ids.isEmpty) return [];
    var query = client
        .from('profiles')
        .select('id,full_name')
        .inFilter('id', ids);
    if (search.trim().isNotEmpty) {
      final escaped = search
          .trim()
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      query = query.ilike('full_name', '%$escaped%');
    }
    final rows = await query.order('full_name').order('id').range(0, 49);
    return rows
        .map(
          (row) => ProfessionalOption(
            id: row['id'] as String,
            name: row['full_name'] as String,
          ),
        )
        .toList();
  }

  Future<List<User>> companyManagers(String companyId) async {
    final client = _client;
    if (client == null) return [MockData.empresaUser];
    final rows = await client
        .from('company_memberships')
        .select('user_id')
        .eq('company_id', companyId)
        .eq('role', 'empresa')
        .range(0, 49);
    final ids = rows.map((row) => row['user_id'] as String).toList();
    if (ids.isEmpty) return [];
    final people = await client
        .from('profiles')
        .select('id,full_name,email')
        .inFilter('id', ids)
        .order('full_name')
        .range(0, 49);
    return people.map((row) {
      final name = row['full_name'] as String;
      return User(
        id: row['id'] as String,
        fullName: name,
        email: row['email'] as String,
        initials: name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join(),
      );
    }).toList();
  }
}

class GestorRepository {
  final SupabaseClient? _injectedClient;
  GestorRepository({SupabaseClient? client}) : _injectedClient = client;

  Future<GestorDashboard> dashboard() async {
    final client =
        _injectedClient ??
        _client ??
        (throw StateError('Configure o Supabase para carregar o painel.'));
    final data = await client.rpc('gestor_dashboard') as Map<String, dynamic>;
    return GestorDashboard(
      companyCount: (data['company_count'] as num).toInt(),
      newCompanyCount: (data['new_company_count'] as num).toInt(),
      userCount: (data['user_count'] as num).toInt(),
      activeUserCount: (data['active_user_count'] as num).toInt(),
      completionPct: (data['completion_pct'] as num?)?.toDouble(),
      growth: (data['growth'] as List<dynamic>).map((item) {
        final row = item as Map<String, dynamic>;
        return GrowthMonth(
          month: DateTime.parse(row['month'] as String),
          companies: (row['companies'] as num).toInt(),
          users: (row['users'] as num).toInt(),
        );
      }).toList(),
      activities: (data['activities'] as List<dynamic>).map((item) {
        final row = item as Map<String, dynamic>;
        return PlatformActivity(
          id: row['id'] as String,
          kind: row['kind'] as String,
          name: row['name'] as String,
          title: row['title'] as String?,
          occurredAt: DateTime.parse(row['occurred_at'] as String),
        );
      }).toList(),
    );
  }
}

class ReportRepository {
  final SupabaseClient? _injectedClient;
  ReportRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get _reportClient =>
      _injectedClient ??
      _client ??
      (throw StateError('Configure o Supabase para carregar relatórios.'));

  Future<List<CompanyCompletion>> platformCompletion({int offset = 0}) async {
    final rows =
        await _reportClient.rpc(
              'gestor_completion',
              params: {'p_offset': offset},
            )
            as List<dynamic>;
    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      return CompanyCompletion(
        companyId: row['company_id'] as String,
        company: row['company'] as String,
        percent: (row['pct'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<PlatformActivityReport> platformActivity({
    required DateTime from,
    required DateTime to,
  }) async {
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final data =
        await _reportClient.rpc(
              'gestor_activity_report',
              params: {'p_from': date(from), 'p_to': date(to)},
            )
            as Map<String, dynamic>;
    return PlatformActivityReport(
      engagement: (data['engagement'] as List<dynamic>).map((item) {
        final row = item as Map<String, dynamic>;
        return EngagementMonth(
          month: DateTime.parse(row['month'] as String),
          activeUsers: (row['active_users'] as num).toInt(),
        );
      }).toList(),
      popularContent: (data['popular_content'] as List<dynamic>).map((item) {
        final row = item as Map<String, dynamic>;
        return PopularContent(
          courseId: row['course_id'] as String,
          title: row['title'] as String,
          kind: row['kind'] as String,
          completions: (row['completions'] as num).toInt(),
        );
      }).toList(),
    );
  }

  Future<double?> completion(String companyId) async {
    final client = _reportClient;
    final row = await client
        .from('completion_by_company')
        .select('pct')
        .eq('company_id', companyId)
        .maybeSingle();
    return (row?['pct'] as num?)?.toDouble();
  }

  Future<List<MapEntry<String, double?>>> departmentCompletion(
    String companyId, {
    int offset = 0,
  }) async {
    final rows = await _reportClient
        .from('completion_by_dept')
        .select('department,pct')
        .eq('company_id', companyId)
        .order('department', ascending: true)
        .range(offset, offset + 49);
    return rows
        .map(
          (row) => MapEntry(
            row['department'] as String? ?? 'Sem departamento',
            (row['pct'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }
}

class ContentRepository {
  final SupabaseClient? _injectedClient;
  ContentRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get _contentClient =>
      _injectedClient ??
      _client ??
      (throw StateError('Configure o Supabase para gerenciar conteúdo.'));

  Future<EditableCourse> detail(String id) async {
    final row = await _contentClient
        .from('courses')
        .select(
          'id,title,description,cover_key,status,all_companies,responsible_id',
        )
        .eq('id', id)
        .single();
    final responsibleId = row['responsible_id'] as String?;
    ProfessionalOption? responsible;
    if (responsibleId != null) {
      final person = await _contentClient
          .from('profiles')
          .select('full_name')
          .eq('id', responsibleId)
          .single();
      responsible = ProfessionalOption(
        id: responsibleId,
        name: person['full_name'] as String,
      );
    }
    final coverKey = row['cover_key'] as String?;
    return EditableCourse(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String? ?? '',
      coverKey: coverKey,
      coverUrl: _publicCoverUrl(coverKey),
      responsible: responsible,
      platformEnabled: row['status'] == 'released',
      allCompanies: row['all_companies'] as bool,
    );
  }

  Future<List<EditableLesson>> editableLessons(
    String courseId, {
    int offset = 0,
  }) async {
    final rows =
        await _contentClient.rpc(
              'gestor_course_lessons',
              params: {'p_course': courseId, 'p_offset': offset},
            )
            as List<dynamic>;
    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      return EditableLesson(
        id: row['id'] as String,
        title: row['title'] as String,
        kind: row['kind'] as String,
        moduleTitle: row['module_title'] as String,
        videoId: row['video_id'] as String?,
      );
    }).toList();
  }

  Future<void> updateMetadata(
    String id, {
    required String title,
    required String description,
    String? coverKey,
    String? responsibleId,
  }) async {
    await _contentClient.rpc(
      'update_course_metadata',
      params: {
        'p_course': id,
        'p_title': title.trim(),
        'p_description': description.trim(),
        'p_cover_key': coverKey,
        'p_responsible_id': responsibleId,
      },
    );
  }

  Future<void> updateLesson(
    String id, {
    required String moduleTitle,
    required String title,
    String? videoId,
  }) async {
    await _contentClient.rpc(
      'update_course_lesson',
      params: {
        'p_lesson': id,
        'p_module_title': moduleTitle.trim(),
        'p_title': title.trim(),
        'p_video_id': videoId,
      },
    );
  }

  Future<List<ManagedContent>> catalog({
    String search = '',
    String? kind,
    int offset = 0,
  }) async {
    final client = _client;
    if (client == null) return [];
    final rows =
        await client.rpc(
              'content_catalog',
              params: {
                'p_search': search.trim(),
                'p_kind': kind,
                'p_offset': offset,
                'p_limit': 50,
              },
            )
            as List<dynamic>;
    return rows.map((item) {
      final row = item as Map<String, dynamic>;
      final coverKey = row['cover_key'] as String?;
      return ManagedContent(
        id: row['id'] as String,
        title: row['title'] as String,
        kind: row['kind'] as String,
        description: row['description'] as String?,
        coverUrl: _publicCoverUrl(coverKey),
        platformEnabled: row['platform_enabled'] as bool,
        allCompanies: row['all_companies'] as bool,
        companyEnabled: row['company_enabled'] as bool,
        companyIds: (row['company_ids'] as List<dynamic>? ?? []).cast<String>(),
        companyCount: (row['company_count'] as num).toInt(),
        lessonCount: (row['lesson_count'] as num).toInt(),
        completionPct: (row['completion_pct'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<void> setPlatformEnabled(String courseId, bool enabled) async {
    await _contentClient.rpc(
      'set_course_platform_enabled',
      params: {'p_course': courseId, 'p_enabled': enabled},
    );
  }

  Future<void> setCompanyEnabled(String courseId, bool enabled) async {
    await _contentClient.rpc(
      'set_course_company_enabled',
      params: {'p_course': courseId, 'p_enabled': enabled},
    );
  }

  Future<ContentAudience> audience(String courseId) async {
    final rows =
        await _contentClient.rpc(
              'gestor_course_audience',
              params: {'p_course': courseId},
            )
            as List<dynamic>;
    final row = rows.single as Map<String, dynamic>;
    return ContentAudience(
      allCompanies: row['all_companies'] as bool,
      companyIds: (row['company_ids'] as List<dynamic>? ?? []).cast<String>(),
    );
  }

  Future<void> setAudience(String courseId, ContentAudience audience) async {
    await _contentClient.rpc(
      'set_course_audience',
      params: {
        'p_course': courseId,
        'p_all_companies': audience.allCompanies,
        'p_company_ids': audience.companyIds,
      },
    );
  }

  Future<String> publishVideo({
    required String title,
    required String description,
    required String moduleTitle,
    required String videoId,
    required ContentAudience audience,
    String? coverKey,
    String? responsibleId,
  }) async =>
      await _contentClient.rpc(
            'publish_video_trail',
            params: {
              'p_title': title.trim(),
              'p_description': description.trim(),
              'p_module_title': moduleTitle.trim(),
              'p_video_id': videoId,
              'p_all_companies': audience.allCompanies,
              'p_company_ids': audience.companyIds,
              'p_cover_key': coverKey,
              'p_responsible_id': responsibleId,
            },
          )
          as String;

  Future<({String key, String putUrl})> requestCoverUpload({
    required int size,
  }) async {
    final response = await _contentClient.functions.invoke(
      'storage-upload-url',
      body: {'prefix': 'covers', 'contentType': 'image/webp', 'size': size},
    );
    final data = response.data as Map<String, dynamic>;
    return (key: data['key'] as String, putUrl: data['putUrl'] as String);
  }

  Future<void> uploadCoverBytes({
    required String putUrl,
    required Uint8List bytes,
  }) async {
    final response = await http.put(
      Uri.parse(putUrl),
      headers: {'Content-Type': 'image/webp'},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cover upload failed.');
    }
  }
}

class CourseRepository {
  LearningCourse _course(Map<String, dynamic> row) => LearningCourse(
    id: row['id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    coverUrl: _publicCoverUrl(row['cover_key'] as String?),
  );

  Future<List<LearningCourse>> available({int offset = 0}) async {
    final client = _client;
    if (client == null) return [];
    final rows = await client
        .from('courses')
        .select('id,title,description,cover_key')
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows.map(_course).toList();
  }

  Future<LearningCourse?> byId(String id) async {
    final client = _client;
    if (client == null) return null;
    final row = await client
        .from('courses')
        .select('id,title,description,cover_key')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : _course(row);
  }

  Future<List<LearningLesson>> lessons(
    String courseId, {
    int offset = 0,
  }) async {
    final client = _client;
    if (client == null) return [];
    final rows = await client
        .from('lessons')
        .select('id,title,kind,modules!inner(title,course_id,position)')
        .eq('modules.course_id', courseId)
        .order('modules(position)')
        .order('position')
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (row) => LearningLesson(
            id: row['id'] as String,
            title: row['title'] as String,
            moduleTitle:
                (row['modules'] as Map<String, dynamic>)['title'] as String,
            kind: CourseKind.values.byName(row['kind'] as String),
          ),
        )
        .toList();
  }
}

class AuthRepository {
  SupabaseClient get _authClient =>
      _client ?? (throw StateError('Configure o Supabase para entrar.'));

  Future<AppSession> login({
    required String email,
    required String password,
  }) async {
    await _authClient.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return (await current())!;
  }

  Future<AppSession?> current() async {
    final client = _client;
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null) return null;
    final profile = await client
        .from('profiles')
        .select('id,full_name,email,needs_password')
        .eq('id', authUser.id)
        .single();
    final contextRows = await client.rpc('available_contexts') as List<dynamic>;
    final contexts = contextRows.map((row) {
      final data = row as Map<String, dynamic>;
      return AccessContext(
        role: Role.values.byName(data['role'] as String),
        companyId: data['company_id'] as String?,
        companyName: data['company_name'] as String,
      );
    }).toList();
    final selected = await client.rpc('selected_context') as List<dynamic>;
    AccessContext? active;
    if (selected.isNotEmpty) {
      final selection = selected.first as Map<String, dynamic>;
      for (final context in contexts) {
        if (context.role.name == selection['role'] &&
            context.companyId == selection['company_id']) {
          active = context;
          break;
        }
      }
    }
    if (active == null && contexts.length == 1) {
      await selectContext(contexts.single);
      active = contexts.single;
    }
    final name = profile['full_name'] as String;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return AppSession(
      user: User(
        id: authUser.id,
        fullName: name,
        email: profile['email'] as String,
        initials: initials,
      ),
      contexts: contexts,
      active: active,
      needsPassword: profile['needs_password'] as bool? ?? false,
    );
  }

  Future<void> selectContext(AccessContext context) async {
    await _authClient.rpc(
      'select_context',
      params: {'p_role': context.role.name, 'p_company_id': context.companyId},
    );
  }

  Future<void> updatePassword(String password) async {
    final client = _authClient;
    await client.auth.updateUser(UserAttributes(password: password));
    await client
        .from('profiles')
        .update({'needs_password': false})
        .eq('id', client.auth.currentUser!.id);
  }

  Future<void> signOut() async {
    if (_client == null) return;
    try {
      await _authClient.rpc('clear_context');
    } catch (_) {
      // The Auth sign-out must still succeed if the network is unavailable.
    } finally {
      await _authClient.auth.signOut();
    }
  }
}

class ProfileRepository {
  final SupabaseClient? _injectedClient;
  ProfileRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get _profileClient =>
      _injectedClient ??
      _client ??
      (throw StateError('Configure o Supabase para editar seu perfil.'));

  Future<OwnProfile> own() async {
    final client = _profileClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Entre para editar seu perfil.');
    final row = await client
        .from('profiles')
        .select('full_name,email,phone,birth_date,address')
        .eq('id', userId)
        .single();
    return OwnProfile(
      fullName: row['full_name'] as String,
      email: row['email'] as String,
      phone: row['phone'] as String? ?? '',
      birthDate: row['birth_date'] as String?,
      address: row['address'] as String? ?? '',
    );
  }

  Future<void> update(OwnProfile profile) async {
    await _profileClient.rpc(
      'update_own_profile',
      params: {
        'p_name': profile.fullName.trim(),
        'p_phone': profile.phone.trim(),
        'p_birth_date': profile.birthDate,
        'p_address': profile.address.trim(),
      },
    );
  }
}

class InvitationRepository {
  Future<List<PendingInvitation>> pending({
    Role? role,
    String? companyId,
  }) async {
    final client = _client;
    if (client == null) return [];
    final rows =
        await client.rpc(
              'pending_invites_page',
              params: {'p_role': role?.name, 'p_company': companyId},
            )
            as List<dynamic>;
    return rows
        .map((row) {
          final data = row as Map<String, dynamic>;
          return PendingInvitation(
            name: data['full_name'] as String?,
            companyName: data['company_name'] as String?,
            email: data['email'] as String,
            role: Role.values.byName(data['role'] as String),
            companyId: data['company_id'] as String?,
          );
        })
        .where(
          (invite) =>
              (role == null || invite.role == role) &&
              (companyId == null || invite.companyId == companyId),
        )
        .toList();
  }

  Future<String> regenerate(PendingInvitation invite) async {
    final client =
        _client ?? (throw StateError('Configure o Supabase para convidar.'));
    final response = await client.functions.invoke(
      'invite-member',
      body: {
        'action': 'regenerate',
        'role': invite.role.name,
        'email': invite.email,
        if (invite.companyId != null) 'companyId': invite.companyId,
      },
    );
    return (response.data as Map<String, dynamic>)['link'] as String;
  }

  Future<String> invite({
    required Role role,
    required String name,
    required String email,
    String? companyId,
    Map<String, String>? company,
    String? department,
    String? jobTitle,
  }) async {
    final client =
        _client ?? (throw StateError('Configure o Supabase para convidar.'));
    final body = <String, dynamic>{
      'role': role.name,
      'name': name.trim(),
      'email': email.trim(),
    };
    if (companyId != null) {
      body['companyId'] = companyId;
    }
    if (company != null) {
      body['company'] = company;
    }
    if (department != null) {
      body['department'] = department;
    }
    if (jobTitle != null) {
      body['jobTitle'] = jobTitle;
    }
    final response = await client.functions.invoke('invite-member', body: body);
    return (response.data as Map<String, dynamic>)['link'] as String;
  }

  Future<void> accept(String token) async {
    final client =
        _client ??
        (throw StateError('Configure o Supabase para aceitar o convite.'));
    await client.functions.invoke('accept-invite', body: {'token': token});
  }
}

final companyRepositoryProvider = Provider<CompanyRepository>(
  (ref) => CompanyRepository(),
);
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(),
);
final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(),
);
final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(),
);
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(),
);
final gestorRepositoryProvider = Provider<GestorRepository>(
  (ref) => GestorRepository(),
);
final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(),
);
final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => CourseRepository(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
final invitationRepositoryProvider = Provider<InvitationRepository>(
  (ref) => InvitationRepository(),
);
