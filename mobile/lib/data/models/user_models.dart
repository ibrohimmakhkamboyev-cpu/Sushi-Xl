class LoginResponse {
  final int userId;
  final String phone;
  final String fullName;
  final String preferredLang;
  final String accessToken;
  final String tokenType;

  LoginResponse({
    required this.userId,
    required this.phone,
    required this.fullName,
    required this.preferredLang,
    required this.accessToken,
    required this.tokenType,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      userId: json['user_id'] as int,
      phone: json['phone'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      preferredLang: json['preferred_lang'] as String? ?? 'ru',
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }
}

class OtpRequestResponse {
  final String status;
  final String delivery;
  final int expiresIn;
  final String debugCode;

  OtpRequestResponse({
    required this.status,
    required this.delivery,
    required this.expiresIn,
    required this.debugCode,
  });

  factory OtpRequestResponse.fromJson(Map<String, dynamic> json) {
    return OtpRequestResponse(
      status: json['status'] as String? ?? 'sent',
      delivery: json['delivery'] as String? ?? 'unknown',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 300,
      debugCode: json['debug_code'] as String? ?? '',
    );
  }
}
