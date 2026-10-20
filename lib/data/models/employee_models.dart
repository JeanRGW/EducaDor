class CourseIncompleteException implements Exception {
  const CourseIncompleteException();
}

class LearningItem {
  final String id, title, state;
  final String? description, coverUrl;
  final int lessonCount, completedCount;
  const LearningItem({
    required this.id,
    required this.title,
    required this.state,
    this.description,
    this.coverUrl,
    required this.lessonCount,
    required this.completedCount,
  });
  double get progress => lessonCount == 0 ? 0 : completedCount / lessonCount;
}

class LearningPage<T> {
  final List<T> items;
  final int total;
  const LearningPage({required this.items, required this.total});
}

class StudyActivity {
  final DateTime day;
  final bool active;
  const StudyActivity(this.day, this.active);
}

class EmployeeSummary {
  final int courseCount, completedCourseCount, certificateCount, balance;
  final String department;
  final List<StudyActivity> activity;
  const EmployeeSummary({
    required this.courseCount,
    required this.completedCourseCount,
    required this.certificateCount,
    required this.balance,
    required this.department,
    required this.activity,
  });
  double? get completion =>
      courseCount == 0 ? null : completedCourseCount / courseCount;
}

class EmployeeLesson {
  final String id, title, moduleId, moduleTitle, kind, status;
  final String? videoId;
  final int positionSec;
  const EmployeeLesson({
    required this.id,
    required this.title,
    required this.moduleId,
    required this.moduleTitle,
    required this.kind,
    required this.status,
    this.videoId,
    required this.positionSec,
  });
  bool get playable => kind == 'video' && videoId != null;
  bool get completed => status == 'completed';
}

class EarnedCertificate {
  final String id, code, courseId, courseTitle, companyName, employeeName;
  final DateTime issuedAt;
  const EarnedCertificate({
    required this.id,
    required this.code,
    required this.courseId,
    required this.courseTitle,
    required this.companyName,
    required this.employeeName,
    required this.issuedAt,
  });
}

class RedeemableReward {
  final String id, title;
  final int cost;
  const RedeemableReward({
    required this.id,
    required this.title,
    required this.cost,
  });
}

class EmployeeRank {
  final String userId, name, department;
  final int points;
  const EmployeeRank({
    required this.userId,
    required this.name,
    required this.department,
    required this.points,
  });
}
