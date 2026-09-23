import 'package:flutter/material.dart';

/// The three experiences in the platform.
enum Role { gestor, empresa, funcionario }

/// Generic content status used across courses/modules/lessons.
enum ContentStatus { completed, inProgress, locked }

enum CourseKind { video, audio, quiz, reading, pdf, module, course }

enum EmployeeStatus { active, onLeave }

class User {
  final String id;
  final String fullName;
  final String email;
  final String initials;

  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.initials,
  });
}

class AccessContext {
  final Role role;
  final String? companyId;
  final String companyName;

  const AccessContext({
    required this.role,
    this.companyId,
    required this.companyName,
  });

  String get label => switch (role) {
    Role.gestor => 'Gestor · Plataforma',
    Role.empresa => 'Gestor da empresa · $companyName',
    Role.funcionario => 'Funcionário · $companyName',
  };
}

class AppSession {
  final User user;
  final List<AccessContext> contexts;
  final AccessContext? active;
  final bool needsPassword;

  const AppSession({
    required this.user,
    required this.contexts,
    this.active,
    this.needsPassword = false,
  });

  Role? get role => active?.role;

  String get homePath => switch (role) {
    Role.funcionario => '/funcionario/home',
    Role.empresa => '/empresa/home',
    Role.gestor => '/gestor/home',
    null => '/contexts',
  };
}

class Company {
  final String id;
  final String name;
  final String cnpj;
  final String responsibleName;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String field;
  final int employeeCount;
  final bool active;
  final String registeredAt;
  final String initials;

  const Company({
    required this.id,
    required this.name,
    required this.cnpj,
    required this.responsibleName,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.state,
    required this.field,
    required this.employeeCount,
    required this.active,
    required this.registeredAt,
    required this.initials,
  });
}

class Employee {
  final String id;
  final String fullName;
  final String initials;
  final String email;
  final String department;
  final String jobTitle;
  final String phone;
  final String birthDate;
  final String address;
  final EmployeeStatus status;
  final double completionPct;
  final String lastActivity;

  const Employee({
    required this.id,
    required this.fullName,
    required this.initials,
    required this.email,
    required this.department,
    required this.jobTitle,
    required this.phone,
    required this.birthDate,
    required this.address,
    required this.status,
    required this.completionPct,
    required this.lastActivity,
  });
}

class Lesson {
  final String id;
  final String title;
  final String subtitle;
  final CourseKind kind;
  final ContentStatus status;
  final String? detail;

  const Lesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.status,
    this.detail,
  });
}

class Module {
  final String id;
  final String title;
  final String duration;
  final double progress;
  final ContentStatus status;
  final String description;
  final String designedBy;
  final String coverColor;
  final List<Lesson> lessons;

  const Module({
    required this.id,
    required this.title,
    required this.duration,
    required this.progress,
    required this.status,
    required this.description,
    required this.designedBy,
    required this.coverColor,
    required this.lessons,
  });
}

class Course {
  final String id;
  final String title;
  final String kindLabel; // "Curso" / "Module"
  final CourseKind kind;
  final String coverColor;
  final String subtitle; // "Modulo 1" / "Modulo 2"
  final String statusLabel; // "Liberado" / "Bloqueado"
  final ContentStatus status;
  final double progress;
  final String meta; // "Video • 5 min restantes"

  const Course({
    required this.id,
    required this.title,
    required this.kindLabel,
    required this.kind,
    required this.coverColor,
    required this.subtitle,
    required this.statusLabel,
    required this.status,
    required this.progress,
    required this.meta,
  });
}

class Reward {
  final String id;
  final String title;
  final int points;
  final String icon;
  final Color color;

  const Reward({
    required this.id,
    required this.title,
    required this.points,
    required this.icon,
    required this.color,
  });
}

class Certificate {
  final String id;
  final String courseName;
  final String earnedAt;
  final String code;

  const Certificate({
    required this.id,
    required this.courseName,
    required this.earnedAt,
    required this.code,
  });
}

class RankingEntry {
  final String name;
  final String department;
  final int points;

  const RankingEntry({
    required this.name,
    required this.department,
    required this.points,
  });
}

class Activity {
  final String id;
  final String icon;
  final Color color;
  final String text;
  final String timeAgo;

  const Activity({
    required this.id,
    required this.icon,
    required this.color,
    required this.text,
    required this.timeAgo,
  });
}

class StatMetric {
  final String label;
  final String value;
  final String? delta;
  final String icon;
  final bool positive;

  const StatMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.delta,
    this.positive = true,
  });
}

class WeeklyStudyDay {
  final String label;
  final double value;

  const WeeklyStudyDay(this.label, this.value);
}
