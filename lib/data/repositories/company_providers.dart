import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../session/session_controller.dart';
import 'repositories.dart';

Duration? _noRetry(int count, Object error) => null;

String _companyId(Ref ref) {
  final identity = ref.watch(
    sessionProvider.select(
      (state) => (
        state.value?.user.id,
        state.value?.active?.role,
        state.value?.active?.companyId,
      ),
    ),
  );
  if (identity.$1 == null ||
      identity.$2 != Role.empresa ||
      identity.$3 == null) {
    throw StateError('Selecione o perfil de gestor da empresa.');
  }
  return identity.$3!;
}

final companyIdentityProvider = FutureProvider.autoDispose<Company>((ref) {
  final id = _companyId(ref);
  return ref.watch(companyRepositoryProvider).byId(id);
}, retry: _noRetry);

final companyDashboardProvider = FutureProvider.autoDispose<CompanyDashboard>((
  ref,
) {
  final id = _companyId(ref);
  return ref.watch(companyDataRepositoryProvider).dashboard(id);
}, retry: _noRetry);

typedef EmployeeQuery = ({String companyId, String search, int offset});

final companyEmployeesProvider = FutureProvider.autoDispose
    .family<EmployeePage, EmployeeQuery>((ref, query) {
      final id = _companyId(ref);
      if (id != query.companyId) {
        return const EmployeePage(items: [], totalCount: 0, filteredCount: 0);
      }
      return ref
          .watch(employeeRepositoryProvider)
          .page(id, search: query.search, offset: query.offset);
    }, retry: _noRetry);

typedef CompanyDepartmentQuery = ({String companyId, int offset});

final companyDepartmentsProvider = FutureProvider.autoDispose
    .family<List<MapEntry<String, double?>>, CompanyDepartmentQuery>((
      ref,
      query,
    ) {
      final id = _companyId(ref);
      if (id != query.companyId) return [];
      return ref
          .watch(reportRepositoryProvider)
          .departmentCompletion(id, offset: query.offset);
    }, retry: _noRetry);
