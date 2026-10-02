import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../session/session_controller.dart';
import 'repositories.dart';

typedef CompanyQuery = ({String search, bool? active, int offset});
typedef ReportPeriod = ({DateTime from, DateTime to});

// Failed reads wait for an explicit retry; Riverpod's automatic backoff would poll.
Duration? _noRetry(int count, Object error) => null;

void _requireGestor(Ref ref) {
  final identity = ref.watch(
    sessionProvider.select(
      (state) => (
        state.value?.user.id,
        state.value?.active?.role,
        state.value?.active?.companyId,
      ),
    ),
  );
  if (identity.$1 == null || identity.$2 != Role.gestor) {
    throw StateError('Selecione o perfil de gestor.');
  }
}

final gestorDashboardProvider = FutureProvider.autoDispose<GestorDashboard>((
  ref,
) {
  _requireGestor(ref);
  return ref.watch(gestorRepositoryProvider).dashboard();
}, retry: _noRetry);

final gestorCompaniesProvider = FutureProvider.autoDispose
    .family<CompanyPage, CompanyQuery>((ref, query) {
      _requireGestor(ref);
      return ref
          .watch(companyRepositoryProvider)
          .page(
            search: query.search,
            active: query.active,
            offset: query.offset,
          );
    }, retry: _noRetry);

final gestorCompletionProvider = FutureProvider.autoDispose
    .family<List<CompanyCompletion>, int>((ref, offset) {
      _requireGestor(ref);
      return ref
          .watch(reportRepositoryProvider)
          .platformCompletion(offset: offset);
    }, retry: _noRetry);

final gestorActivityReportProvider = FutureProvider.autoDispose
    .family<PlatformActivityReport, ReportPeriod>((ref, period) {
      _requireGestor(ref);
      return ref
          .watch(reportRepositoryProvider)
          .platformActivity(from: period.from, to: period.to);
    }, retry: _noRetry);
