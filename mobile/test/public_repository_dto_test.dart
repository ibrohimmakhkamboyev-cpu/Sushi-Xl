import 'package:flutter_test/flutter_test.dart';
import 'package:sushi_xl/data/repositories/public_repository.dart';

void main() {
  test('PublicBannerDto normalizes action and ids', () {
    final dto = PublicBannerDto.fromJson({
      'id': 7,
      'title': ' Promo ',
      'subtitle': ' Hot ',
      'image_url': ' https://cdn/banner.png ',
      'action_type': 'OPEN_PRODUCTS',
      'productIds': [1, 2, 3],
      'product_id': 9,
      'category_id': 4,
      'target_url': ' https://example.com ',
      'isActive': true,
      'sortOrder': 3,
    });

    expect(dto.id, 7);
    expect(dto.title, 'Promo');
    expect(dto.subtitle, 'Hot');
    expect(dto.imageUrl, 'https://cdn/banner.png');
    expect(dto.actionType, 'open_products');
    expect(dto.productId, 9);
    expect(dto.categoryId, 4);
    expect(dto.linkedProductIds, [1, 2, 3]);
    expect(dto.targetUrl, 'https://example.com');
    expect(dto.sortOrder, 3);
  });

  test('PublicSettingsDto trims support copy', () {
    final dto = PublicSettingsDto.fromJson({
      'supportPhone': ' +998900001122 ',
      'timezone': ' Asia/Tashkent ',
      'currencyCode': ' UZS ',
      'callLabel': ' Call ',
      'chatLabel': ' Chat ',
      'chatSubtitle': ' Ask us ',
      'chatIntro': ' Hello ',
    });

    expect(dto.supportPhone, '+998900001122');
    expect(dto.timezone, 'Asia/Tashkent');
    expect(dto.currencyCode, 'UZS');
    expect(dto.callLabel, 'Call');
    expect(dto.chatLabel, 'Chat');
    expect(dto.chatSubtitle, 'Ask us');
    expect(dto.chatIntro, 'Hello');
  });

}
