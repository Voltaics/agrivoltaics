import 'package:cloud_firestore/cloud_firestore.dart';

/// High-level alert rule types.
enum AlertRuleType {
  threshold,
  frostWarning,
  moldRisk,
  blackRotRisk,
}

extension AlertRuleTypeExtension on AlertRuleType {
  String get value {
    switch (this) {
      case AlertRuleType.threshold:
        return 'threshold';
      case AlertRuleType.frostWarning:
        return 'frost_warning';
      case AlertRuleType.moldRisk:
        return 'mold_risk';
      case AlertRuleType.blackRotRisk:
        return 'black_rot_risk';
    }
  }

  String get label {
    switch (this) {
      case AlertRuleType.threshold:
        return 'Threshold';
      case AlertRuleType.frostWarning:
        return 'Frost Warning';
      case AlertRuleType.moldRisk:
        return 'Mold Risk';
      case AlertRuleType.blackRotRisk:
        return 'Black Rot Risk';
    }
  }

  static AlertRuleType fromString(String? s) {
    switch (s) {
      case 'frost_warning':
        return AlertRuleType.frostWarning;
      case 'mold_risk':
        return AlertRuleType.moldRisk;
      case 'black_rot_risk':
        return AlertRuleType.blackRotRisk;
      case 'threshold':
      default:
        return AlertRuleType.threshold;
    }
  }
}

/// Supported comparison operators for threshold alert rule conditions.
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

  String get value => name;

  static AlertOperator fromString(String s) {
    return AlertOperator.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AlertOperator.gt,
    );
  }
}

/// An alert rule stored under organizations/{orgId}/alertRules/{ruleId}.
///
/// Supports:
/// - threshold rules: one field/operator/threshold
/// - frost warning rules: compound condition stored in [ruleConfig]
class AlertRule {
  final String id;
  final String name;

  /// Rule kind.
  final AlertRuleType ruleType;

  /// Used for threshold rules. Can be blank for non-threshold rules.
  final String fieldAlias;

  /// Used for threshold rules only.
  final AlertOperator? operator;

  /// Used for threshold rules only.
  final double? threshold;

  /// Used for frost warning rules.
  ///
  /// Suggested keys:
  /// - tempDropRateFPerHour
  /// - humidityMin
  /// - airTempMaxF
  /// - soilTempMaxF
  /// - lightMax
  /// - requireLowLight
  final Map<String, dynamic>? ruleConfig;

  final bool enabled;
  final List<String> notifyUserIds;

  /// Seasonal start date "MM/dd". Null = no restriction.
  final String? activeRangeStart;

  /// Seasonal end date "MM/dd". Null = no restriction.
  final String? activeRangeEnd;

  /// Minimum minutes between repeated alerts for this rule.
  final int cooldownMinutes;

  /// When this rule last fired (set by backend).
  final DateTime? lastFiredAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  const AlertRule({
    required this.id,
    required this.name,
    required this.ruleType,
    required this.fieldAlias,
    this.operator,
    this.threshold,
    this.ruleConfig,
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

  bool get isThresholdRule => ruleType == AlertRuleType.threshold;
  bool get isFrostWarningRule => ruleType == AlertRuleType.frostWarning;

  factory AlertRule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlertRule(
      id: doc.id,
      name: data['name'] ?? '',
      ruleType: AlertRuleTypeExtension.fromString(data['ruleType'] as String?),
      fieldAlias: data['fieldAlias'] ?? '',
      operator: data['operator'] != null
          ? AlertOperatorExtension.fromString(data['operator'])
          : null,
      threshold: (data['threshold'] as num?)?.toDouble(),
      ruleConfig: data['ruleConfig'] != null
          ? Map<String, dynamic>.from(data['ruleConfig'])
          : null,
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
      'ruleType': ruleType.value,
      'fieldAlias': fieldAlias,
      'operator': operator?.value,
      'threshold': threshold,
      'ruleConfig': ruleConfig,
      'enabled': enabled,
      'notifyUserIds': notifyUserIds,
      'activeRangeStart': activeRangeStart,
      'activeRangeEnd': activeRangeEnd,
      'cooldownMinutes': cooldownMinutes,
      'lastFiredAt':
          lastFiredAt != null ? Timestamp.fromDate(lastFiredAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  AlertRule copyWith({
    String? name,
    AlertRuleType? ruleType,
    String? fieldAlias,
    Object? operator = _sentinel,
    Object? threshold = _sentinel,
    Object? ruleConfig = _sentinel,
    bool? enabled,
    List<String>? notifyUserIds,
    int? cooldownMinutes,
    Object? activeRangeStart = _sentinel,
    Object? activeRangeEnd = _sentinel,
    Object? lastFiredAt = _sentinel,
  }) {
    return AlertRule(
      id: id,
      name: name ?? this.name,
      ruleType: ruleType ?? this.ruleType,
      fieldAlias: fieldAlias ?? this.fieldAlias,
      operator: operator == _sentinel ? this.operator : operator as AlertOperator?,
      threshold: threshold == _sentinel ? this.threshold : threshold as double?,
      ruleConfig: ruleConfig == _sentinel
          ? this.ruleConfig
          : ruleConfig as Map<String, dynamic>?,
      enabled: enabled ?? this.enabled,
      notifyUserIds: notifyUserIds ?? this.notifyUserIds,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      activeRangeStart: activeRangeStart == _sentinel
          ? this.activeRangeStart
          : activeRangeStart as String?,
      activeRangeEnd: activeRangeEnd == _sentinel
          ? this.activeRangeEnd
          : activeRangeEnd as String?,
      lastFiredAt: lastFiredAt == _sentinel
          ? this.lastFiredAt
          : lastFiredAt as DateTime?,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      createdBy: createdBy,
    );
  }
}

const Object _sentinel = Object();