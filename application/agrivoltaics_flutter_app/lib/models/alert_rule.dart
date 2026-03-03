import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported comparison operators for alert rule conditions.
enum AlertOperator { gt, lt, gte, lte, eq }

extension AlertOperatorExtension on AlertOperator {
  String get label {
    switch (this) {
      case AlertOperator.gt:
        return '>';
      case AlertOperator.lt:
        return '<';
      case AlertOperator.gte:
        return '≥';
      case AlertOperator.lte:
        return '≤';
      case AlertOperator.eq:
        return '=';
    }
  }

  String get value {
    return name; // 'gt', 'lt', 'gte', 'lte', 'eq'
  }

  static AlertOperator fromString(String s) {
    return AlertOperator.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AlertOperator.gt,
    );
  }
}

/// An alert rule stored under organizations/{orgId}/alertRules/{ruleId}.
///
/// A rule watches a specific sensor reading field across the whole organization
/// and sends FCM push notifications to [notifyUserIds] when the condition
/// ([fieldAlias] [operator] [threshold]) is met.
///
/// Optional [activeTimeStart] / [activeTimeEnd] restrict the window during
/// which the rule is evaluated (24-hour HH:mm format, e.g. "22:00").
/// If both are null the rule is active at all times.
class AlertRule {
  final String id;
  final String name;
  final String fieldAlias;
  final AlertOperator operator;
  final double threshold;
  final bool enabled;
  final List<String> notifyUserIds;

  /// 24-hour time string "HH:mm" (e.g. "22:00"). Null = no restriction.
  final String? activeTimeStart;

  /// 24-hour time string "HH:mm" (e.g. "06:00"). Null = no restriction.
  final String? activeTimeEnd;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  AlertRule({
    required this.id,
    required this.name,
    required this.fieldAlias,
    required this.operator,
    required this.threshold,
    required this.enabled,
    required this.notifyUserIds,
    this.activeTimeStart,
    this.activeTimeEnd,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory AlertRule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlertRule(
      id: doc.id,
      name: data['name'] ?? '',
      fieldAlias: data['fieldAlias'] ?? '',
      operator: AlertOperatorExtension.fromString(data['operator'] ?? 'gt'),
      threshold: (data['threshold'] as num?)?.toDouble() ?? 0.0,
      enabled: data['enabled'] ?? true,
      notifyUserIds: List<String>.from(data['notifyUserIds'] ?? []),
      activeTimeStart: data['activeTimeStart'] as String?,
      activeTimeEnd: data['activeTimeEnd'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'fieldAlias': fieldAlias,
      'operator': operator.value,
      'threshold': threshold,
      'enabled': enabled,
      'notifyUserIds': notifyUserIds,
      'activeTimeStart': activeTimeStart,
      'activeTimeEnd': activeTimeEnd,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  AlertRule copyWith({
    String? name,
    String? fieldAlias,
    AlertOperator? operator,
    double? threshold,
    bool? enabled,
    List<String>? notifyUserIds,
    Object? activeTimeStart = _sentinel,
    Object? activeTimeEnd = _sentinel,
  }) {
    return AlertRule(
      id: id,
      name: name ?? this.name,
      fieldAlias: fieldAlias ?? this.fieldAlias,
      operator: operator ?? this.operator,
      threshold: threshold ?? this.threshold,
      enabled: enabled ?? this.enabled,
      notifyUserIds: notifyUserIds ?? this.notifyUserIds,
      activeTimeStart: activeTimeStart == _sentinel
          ? this.activeTimeStart
          : activeTimeStart as String?,
      activeTimeEnd:
          activeTimeEnd == _sentinel ? this.activeTimeEnd : activeTimeEnd as String?,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      createdBy: createdBy,
    );
  }
}

// Private sentinel for copyWith nullable fields.
const Object _sentinel = Object();
