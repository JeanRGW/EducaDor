import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../mock/mock_data.dart';
import '../models/models.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

SupabaseClient? get _client =>
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty
    ? Supabase.instance.client
    : null;

class CompanyRepository {
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
    final companies = await all();
    return companies.firstWhere((company) => company.id == id);
  }
}

class EmployeeRepository {
  Future<List<Employee>> all(String companyId) async {
    final client = _client;
    if (client == null) return MockData.employees;
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
        lastActivity: '',
      );
    }).toList();
  }
}

class PeopleRepository {
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

  Future<List<String>> pending(String role) async {
    final client = _client;
    if (client == null) return [];
    final rows = await client.rpc('pending_invites') as List<dynamic>;
    return rows
        .where((row) => (row as Map<String, dynamic>)['role'] == role)
        .map((row) => (row as Map<String, dynamic>)['email'] as String)
        .toList();
  }
}

class ReportRepository {
  Future<double?> completion(String companyId) async {
    final client = _client;
    if (client == null) return null;
    final row = await client
        .from('completion_by_company')
        .select('pct')
        .eq('company_id', companyId)
        .maybeSingle();
    return (row?['pct'] as num?)?.toDouble();
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

class InvitationRepository {
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
final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(),
);
final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(),
);
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
final invitationRepositoryProvider = Provider<InvitationRepository>(
  (ref) => InvitationRepository(),
);
