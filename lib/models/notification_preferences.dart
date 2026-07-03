class NotificationPreferences {
  NotificationPreferences({
    required this.disabledAll,
    required this.disabledTypes,
  });

  final bool disabledAll;
  final Map<String, bool> disabledTypes;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final disabledTypes = <String, bool>{};
    final raw = json['disabledTypes'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is bool) {
          disabledTypes[key] = value;
        }
      }
    }
    return NotificationPreferences(
      disabledAll: json['disabledAll'] as bool? ?? false,
      disabledTypes: disabledTypes,
    );
  }

  NotificationPreferences copyWith({
    bool? disabledAll,
    Map<String, bool>? disabledTypes,
  }) {
    return NotificationPreferences(
      disabledAll: disabledAll ?? this.disabledAll,
      disabledTypes: disabledTypes ?? this.disabledTypes,
    );
  }
}

