import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/menu_models.dart';
import '../../data/repositories/catalog_repository.dart';
import 'providers.dart';

final catalogRepositoryProvider =
    Provider((ref) => CatalogRepository(ref.read(dioProvider)));

final discountedProductsProvider = FutureProvider<List<ProductModel>>((ref) async {
  final locale = ref.watch(localeProvider);
  return ref
      .read(catalogRepositoryProvider)
      .listProducts(discounted: true, lang: locale.languageCode);
});

final productDetailsProvider =
    FutureProvider.family<ProductModel, int>((ref, productId) async {
  final locale = ref.watch(localeProvider);
  return ref
      .read(catalogRepositoryProvider)
      .getProduct(productId, lang: locale.languageCode);
});

final recommendedDrinksProvider =
    FutureProvider.family<List<ProductModel>, int>((ref, productId) async {
  final locale = ref.watch(localeProvider);
  return ref
      .read(catalogRepositoryProvider)
      .fetchRecommendedDrinks(
          productId: productId, limit: 6, lang: locale.languageCode);
});
