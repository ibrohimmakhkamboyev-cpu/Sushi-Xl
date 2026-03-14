import 'package:dio/dio.dart';

import '../models/menu_models.dart';

class CatalogRepository {
  final Dio _dio;

  CatalogRepository(this._dio);

  Future<List<ProductModel>> listProducts({
    bool discounted = false,
    String? category,
    int? categoryId,
    int? limit,
    String lang = 'ru',
  }) async {
    final res = await _dio.get(
      '/products',
      queryParameters: {
        if (discounted) 'discounted': true,
        if (category != null && category.trim().isNotEmpty) 'category': category,
        if (categoryId != null) 'categoryId': categoryId,
        if (limit != null) 'limit': limit,
        'lang': lang,
      },
    );
    final rows = (res.data['results'] as List<dynamic>? ?? const []);
    return rows
        .whereType<Map>()
        .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ProductModel> getProduct(int id, {String lang = 'ru'}) async {
    final res = await _dio.get('/products/$id', queryParameters: {'lang': lang});
    return ProductModel.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<List<ProductModel>> fetchRecommendedDrinks({
    int? productId,
    int limit = 6,
    String lang = 'ru',
  }) async {
    final res = await _dio.get(
      '/recommendations/drinks',
      queryParameters: {
        if (productId != null) 'productId': productId,
        'limit': limit,
        'lang': lang,
      },
    );
    final rows = (res.data['results'] as List<dynamic>? ?? const []);
    return rows
        .whereType<Map>()
        .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CategoryModel>> listCategories({String lang = 'ru'}) async {
    final res = await _dio.get('/categories', queryParameters: {'lang': lang});
    final rows = (res.data['results'] as List<dynamic>? ?? const []);
    return rows
        .whereType<Map>()
        .map((e) => CategoryModel.fromJson({...Map<String, dynamic>.from(e), 'products': const []}))
        .toList();
  }
}
