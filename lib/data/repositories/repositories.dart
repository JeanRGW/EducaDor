import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_data.dart';
import '../models/models.dart';

/// Thin async façade over [MockData]. Repositories are intentionally
/// synchronous-backed for the mock phase; swapping to an API layer later only
/// requires re-implementing these interfaces.
class CompanyRepository {
  Future<List<Company>> all() async => MockData.companies;
  Future<Company> byId(String id) async => MockData.companyById(id);
}

class EmployeeRepository {
  Future<List<Employee>> all() async => MockData.employees;
}

class AuthRepository {
  /// Returns the [User] for the given role. Mock credentials are accepted as
  /// long as the fields are non-empty; real validation lands with the API.
  Future<(User, Company?, Employee?)> login({
    required Role role,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    switch (role) {
      case Role.gestor:
        return (MockData.gestor, null, null);
      case Role.empresa:
        return (MockData.empresaUser, MockData.companyById('c-santa-maria'), null);
      case Role.funcionario:
        return (
          MockData.funcionarioUser,
          MockData.companyById('c-santa-maria'),
          MockData.employees.first,
        );
    }
  }
}

final companyRepositoryProvider = Provider<CompanyRepository>((ref) => CompanyRepository());
final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) => EmployeeRepository());
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());
