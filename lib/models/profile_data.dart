class ProfileData {
  ProfileData({
    required this.email,
    required this.roles,
    this.clienteId,
    this.tecnicoId,
    this.operadorId,
  });

  final String email;
  final List<String> roles;
  final int? clienteId;
  final int? tecnicoId;
  final int? operadorId;

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final roles = (user['roles'] as List<dynamic>? ?? [])
        .map((item) => (item as Map<String, dynamic>)['name'] as String)
        .toList();

    return ProfileData(
      email: user['email'] as String? ?? '',
      roles: roles,
      clienteId: json['cliente_id'] as int?,
      tecnicoId: json['tecnico_id'] as int?,
      operadorId: json['operador_id'] as int?,
    );
  }
}
