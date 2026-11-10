import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../session/session_controller.dart';
import 'repositories.dart';

typedef EmployeeScope = ({String userId, String companyId});
final employeeScopeProvider = Provider<EmployeeScope>((ref) {
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
      identity.$2 != Role.funcionario ||
      identity.$3 == null) {
    throw StateError('Selecione o perfil de funcionário.');
  }
  return (userId: identity.$1!, companyId: identity.$3!);
});
final employeeGenderProvider = Provider<Gender?>(
  (ref) =>
      ref.watch(sessionProvider.select((state) => state.value?.user.gender)),
);
Duration? _noRetry(int count, Object error) => null;
final employeeSummaryProvider = FutureProvider.autoDispose<EmployeeSummary>((
  ref,
) {
  final scope = ref.watch(employeeScopeProvider);
  return ref.watch(employeeLearningRepositoryProvider).summary(scope.companyId);
}, retry: _noRetry);
typedef LearningQuery = ({
  EmployeeScope scope,
  String search,
  String? kind,
  String? state,
  int offset,
});
final learningCatalogProvider = FutureProvider.autoDispose
    .family<LearningPage<LearningItem>, LearningQuery>((ref, query) {
      final scope = ref.watch(employeeScopeProvider);
      if (scope != query.scope) return const LearningPage(items: [], total: 0);
      return ref
          .watch(employeeLearningRepositoryProvider)
          .catalog(
            scope.companyId,
            search: query.search,
            kind: query.kind,
            state: query.state,
            offset: query.offset,
          );
    }, retry: _noRetry);
typedef LessonQuery = ({EmployeeScope scope, String courseId, int offset});
typedef ScopedPage = ({EmployeeScope scope, int offset});
final employeeCourseProvider = FutureProvider.autoDispose
    .family<LearningCourse?, String>((ref, id) {
      ref.watch(employeeScopeProvider);
      return ref.watch(employeeLearningRepositoryProvider).course(id);
    }, retry: _noRetry);
final employeeLessonsProvider = FutureProvider.autoDispose
    .family<LearningPage<EmployeeLesson>, LessonQuery>((ref, query) {
      final scope = ref.watch(employeeScopeProvider);
      ref.watch(employeeGenderProvider);
      if (scope != query.scope) return const LearningPage(items: [], total: 0);
      return ref
          .watch(employeeLearningRepositoryProvider)
          .lessons(scope.companyId, query.courseId, offset: query.offset);
    }, retry: _noRetry);
final employeeCertificatesProvider = FutureProvider.autoDispose
    .family<LearningPage<EarnedCertificate>, ScopedPage>((ref, query) {
      final scope = ref.watch(employeeScopeProvider);
      if (scope != query.scope) return const LearningPage(items: [], total: 0);
      return ref
          .watch(employeeLearningRepositoryProvider)
          .certificates(scope.companyId, offset: query.offset);
    }, retry: _noRetry);
final courseCertificateProvider = FutureProvider.autoDispose
    .family<bool, ({EmployeeScope scope, String courseId})>((ref, query) async {
      if (ref.watch(employeeScopeProvider) != query.scope) return false;
      final exists = await ref
          .watch(employeeLearningRepositoryProvider)
          .hasCourseCertificate(
            query.scope.userId,
            query.scope.companyId,
            query.courseId,
          );
      if (!ref.mounted || ref.read(employeeScopeProvider) != query.scope) {
        return false;
      }
      return exists;
    }, retry: _noRetry);
final employeeRewardsProvider = FutureProvider.autoDispose
    .family<List<RedeemableReward>, ScopedPage>((ref, query) {
      final scope = ref.watch(employeeScopeProvider);
      if (scope != query.scope) return [];
      return ref
          .watch(employeeLearningRepositoryProvider)
          .rewards(offset: query.offset);
    }, retry: _noRetry);
final employeeRankingProvider = FutureProvider.autoDispose<List<EmployeeRank>>((
  ref,
) {
  final scope = ref.watch(employeeScopeProvider);
  return ref.watch(employeeLearningRepositoryProvider).ranking(scope.companyId);
}, retry: _noRetry);

void refreshLearning(WidgetRef ref) {
  ref.invalidate(employeeSummaryProvider);
  ref.invalidate(learningCatalogProvider);
  ref.invalidate(employeeLessonsProvider);
  ref.invalidate(employeeCertificatesProvider);
  ref.invalidate(employeeRankingProvider);
}
