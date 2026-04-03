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
/// A rule watches a specific sensor reading field and sends FCM push
/// notifications to [notifyUserIds] when the condition
/// ([fieldAlias] [operator] [threshold]) is met.
///
/// Optional [activeRangeStart] / [activeRangeEnd] restrict the rule to a
/// seasonal date window in "MM/dd" format (e.g. "11/01" → "03/15" for
/// frost season). Handles year wrap-around. Both null = always active.
///
/// [cooldownMinutes] prevents repeated alerts within the given window.
class AlertRule {
  final String id;
  final String name;
  final String fieldAlias;
  final AlertOperator operator;
  final double threshold;
  final bool enabled;
  final List<String> notifyUserIds;

  /// Seasonal start date "MM/dd" (e.g. "11/01"). Null = no restriction.
  final String? activeRangeStart;

  /// Seasonal end date "MM/dd" (e.g. "03/15"). Null = no restriction.
  final String? activeRangeEnd;

  /// Minimum minutes between repeated alerts for this rule. 0 = no cooldown.
  final int cooldownMinutes;

  /// When this rule last fired (set by the backend). Used for cooldown checks.
  final DateTime? lastFiredAt;

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
    this.activeRangeStart,
    this.activeRangeEnd,
    this.cooldownMinutes = 60,
    this.lastFiredAt,
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
      activeRangeStart: data['activeRangeStart'] as String?,
      activeRangeEnd: data['activeRangeEnd'] as String?,
      cooldownMinutes: (data['cooldownMinutes'] as num?)?.toInt() ?? 60,
      lastFiredAt: (data['lastFiredAt'] as Timestamp?)?.toDate(),
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
      'activeRangeStart': activeRangeStart,
      'activeRangeEnd': activeRangeEnd,
      'cooldownMinutes': cooldownMinutes,
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
    int? cooldownMinutes,
    Object? activeRangeStart = _sentinel,
    Object? activeRangeEnd = _sentinel,
  }) {
    return AlertRule(
      id: id,
      name: name ?? this.name,
      fieldAlias: fieldAlias ?? this.fieldAlias,
      operator: operator ?? this.operator,
      threshold: threshold ?? this.threshold,
      enabled: enabled ?? this.enabled,
      notifyUserIds: notifyUserIds ?? this.notifyUserIds,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      activeRangeStart: activeRangeStart == _sentinel
          ? this.activeRangeStart
          : activeRangeStart as String?,
      activeRangeEnd: activeRangeEnd == _sentinel
          ? this.activeRangeEnd
          : activeRangeEnd as String?,
      lastFiredAt: lastFiredAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      createdBy: createdBy,
    );
  }
}

// Private sentinel for copyWith nullable fields.
const Object _sentinel = Object();
