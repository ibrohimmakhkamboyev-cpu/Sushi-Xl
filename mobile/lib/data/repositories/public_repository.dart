import 'package:dio/dio.dart';

class WorkingHourDto {
  final int day;
  final String opensAt;
  final String closesAt;
  final bool isClosed;

  WorkingHourDto({
    required this.day,
    required this.opensAt,
    required this.closesAt,
    required this.isClosed,
  });

  factory WorkingHourDto.fromJson(Map<String, dynamic> json) {
    return WorkingHourDto(
      day: json['day'] as int,
      opensAt: json['opens_at'] as String? ?? '',
      closesAt: json['closes_at'] as String? ?? '',
      isClosed: json['is_closed'] as bool? ?? false,
    );
  }
}

class PublicRepository {
  final Dio _dio;
  PublicRepository(this._dio);

  Future<List<WorkingHourDto>> getWorkingHours() async {
    final res = await _dio.get('/public/hours');
    final data = res.data['hours'] as List<dynamic>;
    return data
        .map((e) => WorkingHourDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicBannerDto>> getBanners({String lang = 'ru'}) async {
    final res =
        await _dio.get('/public/banners', queryParameters: {'lang': lang});
    final data = res.data['results'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PublicBannerDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<PublicNotificationDto>> getNotifications(
      {String lang = 'ru'}) async {
    final res = await _dio
        .get('/public/notifications', queryParameters: {'lang': lang});
    final data = res.data['results'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map>()
        .map(
            (e) => PublicNotificationDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<PublicFaqDto>> getFaqs({String lang = 'ru'}) async {
    final res = await _dio.get('/public/faqs', queryParameters: {'lang': lang});
    final data = res.data['results'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map>()
        .map((e) => PublicFaqDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PublicSettingsDto?> getSettings({String lang = 'ru'}) async {
    final res =
        await _dio.get('/public/settings', queryParameters: {'lang': lang});
    final raw = res.data;
    if (raw is! Map) return null;
    return PublicSettingsDto.fromJson(Map<String, dynamic>.from(raw));
  }
}

class PublicBannerDto {
  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String actionType;
  final int? productId;
  final int? categoryId;
  final List<int> linkedProductIds;
  final String? targetUrl;
  final bool isActive;
  final int sortOrder;

  PublicBannerDto({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.actionType,
    required this.productId,
    required this.categoryId,
    required this.linkedProductIds,
    required this.targetUrl,
    required this.isActive,
    required this.sortOrder,
  });

  List<int> get productIds => linkedProductIds;

  factory PublicBannerDto.fromJson(Map<String, dynamic> json) {
    final rawLinkedProducts = (json['linkedProductIds'] as List<dynamic>?) ??
        (json['productIds'] as List<dynamic>?) ??
        const [];
    final normalizedAction = (json['actionType'] as String? ??
            json['action_type'] as String? ??
            'none')
        .trim()
        .toLowerCase();
    final parsedProductId =
        (json['productId'] as num? ?? json['product_id'] as num?)?.toInt();
    final rawTargetUrl =
        (json['targetUrl'] as String? ?? json['target_url'] as String? ?? '')
            .trim();
    return PublicBannerDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      subtitle: (json['subtitle'] as String? ?? '').trim(),
      imageUrl:
          (json['imageUrl'] as String? ?? json['image_url'] as String? ?? '')
              .trim(),
      actionType: normalizedAction,
      productId: parsedProductId,
      categoryId:
          (json['categoryId'] as num? ?? json['category_id'] as num?)?.toInt(),
      linkedProductIds: rawLinkedProducts
          .map((v) => (v as num?)?.toInt())
          .whereType<int>()
          .toList(),
      targetUrl: rawTargetUrl.isEmpty ? null : rawTargetUrl,
      isActive: json['isActive'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

class PublicNotificationDto {
  final int id;
  final String title;
  final String message;
  final String imageUrl;
  final String type;
  final bool isActive;
  final String createdAt;

  PublicNotificationDto({
    required this.id,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.type,
    required this.isActive,
    required this.createdAt,
  });

  factory PublicNotificationDto.fromJson(Map<String, dynamic> json) {
    return PublicNotificationDto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      message: (json['message'] as String? ?? '').trim(),
      imageUrl:
          (json['imageUrl'] as String? ?? json['image_url'] as String? ?? '')
              .trim(),
      type: (json['type'] as String? ?? 'info').trim(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: (json['createdAt'] as String? ?? '').trim(),
    );
  }
}

class PublicFaqDto {
  final String id;
  final String question;
  final String answer;
  final bool isActive;
  final int sortOrder;

  PublicFaqDto({
    required this.id,
    required this.question,
    required this.answer,
    required this.isActive,
    required this.sortOrder,
  });

  factory PublicFaqDto.fromJson(Map<String, dynamic> json) {
    return PublicFaqDto(
      id: ((json['id'] as num?)?.toInt() ?? 0).toString(),
      question: (json['question'] as String? ?? '').trim(),
      answer: (json['answer'] as String? ?? '').trim(),
      isActive: json['isActive'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

class PublicSettingsDto {
  final String supportPhone;
  final String timezone;
  final String currencyCode;
  final String callLabel;
  final String chatLabel;
  final String chatSubtitle;
  final String chatIntro;

  PublicSettingsDto({
    required this.supportPhone,
    required this.timezone,
    required this.currencyCode,
    required this.callLabel,
    required this.chatLabel,
    required this.chatSubtitle,
    required this.chatIntro,
  });

  factory PublicSettingsDto.fromJson(Map<String, dynamic> json) {
    return PublicSettingsDto(
      supportPhone: (json['supportPhone'] as String? ?? '').trim(),
      timezone: (json['timezone'] as String? ?? 'Asia/Tashkent').trim(),
      currencyCode: (json['currencyCode'] as String? ?? 'UZS').trim(),
      callLabel: (json['callLabel'] as String? ?? '').trim(),
      chatLabel: (json['chatLabel'] as String? ?? '').trim(),
      chatSubtitle: (json['chatSubtitle'] as String? ?? '').trim(),
      chatIntro: (json['chatIntro'] as String? ?? '').trim(),
    );
  }
}
