import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/menu_models.dart';
import '../../core/cache/menu_cache.dart';
import '../../core/config.dart';

class MenuRepository {
  final Dio _dio;
  final MenuCache _cache = MenuCache();
  Map<String, String>? _assetImageByName;
  static const String _cacheSourceKey = '__source';
  static const String _backendSource = 'backend';
  MenuRepository(this._dio);

  Future<MenuResponse> fetchMenu(String lang) async {
    Map<String, dynamic>? source;
    try {
      source = await _loadBaseMenu(lang);
    } catch (e) {
      debugPrint('[menu] base load failed: $e');
      source = null;
    }

    if (source != null) {
      try {
        return MenuResponse.fromJson(_localizedMenuJson(source, lang));
      } catch (e) {
        debugPrint('[menu] parse failed, returning empty menu: $e');
      }
    }

    // Last-resort fallback to keep UI working even when backend/cache payloads
    // are unavailable or malformed.
    return MenuResponse(categories: const []);
  }

  Future<Map<String, dynamic>?> _loadBaseMenu(String lang) async {
    if (!useBackend) {
      debugPrint('[menu] menu load blocked: USE_BACKEND=false is not allowed.');
      return null;
    }

    try {
      final res = await _dio.get('/menu', queryParameters: {'lang': lang});
      final data = (res.data as Map).cast<String, dynamic>();
      final tagged = _tagSource(data, _backendSource);
      await _cache.save(tagged);
      return tagged;
    } catch (e) {
      debugPrint('[menu] backend fetch failed: $e');
      final cached = await _cache.load();
      if (cached != null) {
        debugPrint('[menu] using cached backend menu');
        return cached;
      }
      return null;
    }
  }

  Map<String, dynamic> _tagSource(Map<String, dynamic> data, String source) {
    final tagged = Map<String, dynamic>.from(data);
    tagged[_cacheSourceKey] = source;
    return tagged;
  }

  // ignore: unused_element
  Future<Map<String, dynamic>?> _loadMenuFromPoster() async {
    if (posterApiToken.trim().isEmpty) {
      debugPrint('[menu] poster skipped: POSTER_API_TOKEN is empty');
      return null;
    }
    final categoriesRaw = await _fetchPosterRows(
      path: posterCategoriesPath,
      extra: const {'type': 'products'},
    );
    final productsRaw = await _fetchPosterRows(path: posterProductsPath);
    if (productsRaw.isEmpty) return null;

    final categoryNameById = <String, String>{};
    for (final row in categoriesRaw) {
      final categoryId = _posterVal(
        row,
        const ['category_id', 'menu_category_id', 'id'],
      );
      final categoryName = _posterVal(
        row,
        const ['category_name', 'name', 'category'],
      );
      if (categoryId.isNotEmpty && categoryName.isNotEmpty) {
        categoryNameById[categoryId] = categoryName;
      }
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    var seqId = 1;
    for (final row in productsRaw) {
      final name = _posterVal(
        row,
        const ['product_name', 'name', 'product', 'product_ru'],
      );
      if (name.isEmpty) continue;
      final categoryId = _posterVal(
        row,
        const ['menu_category_id', 'category_id', 'categoryId'],
      );
      final categoryName = _posterVal(
        row,
        const ['category_name', 'category', 'menu_category_name'],
      );
      final category = categoryNameById[categoryId] ??
          (categoryName.isNotEmpty ? categoryName : 'Без категории');
      final productId = _posterInt(
            row,
            const ['product_id', 'id', 'productId'],
          ) ??
          seqId++;
      final price =
          _posterPrice(row, const ['price', 'price1', 'cost', 'spots_price']) ??
              0;
      final description = _posterVal(
        row,
        const ['product_description', 'description', 'desc'],
      );
      final image = _posterVal(
        row,
        const ['photo_origin', 'photo', 'image', 'image_url'],
      );
      grouped.putIfAbsent(category, () => []).add({
        'id': productId,
        'name': name,
        'description': description.isEmpty ? null : description,
        'price': price,
        'image_url': image.isEmpty ? null : image,
        'modifiers': const <Map<String, dynamic>>[],
      });
    }
    if (grouped.isEmpty) return null;

    var categoryId = 1;
    final categories = grouped.entries.map((entry) {
      return <String, dynamic>{
        'id': categoryId++,
        'name': entry.key,
        'description': null,
        'products': entry.value,
      };
    }).toList();
    return {'categories': categories};
  }

  Future<List<Map<String, dynamic>>> _fetchPosterRows({
    required String path,
    Map<String, dynamic> extra = const {},
  }) async {
    final options = BaseOptions(
      baseUrl: _effectivePosterBaseUrl(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    );
    final dio = Dio(options);
    final params = <String, dynamic>{
      'token': posterApiToken,
      if (posterAccount.trim().isNotEmpty) 'account_name': posterAccount.trim(),
      ...extra,
    };
    final response = await dio.get(path, queryParameters: params);
    final body = response.data;
    final raw = _unwrapPosterCollection(body);
    return raw
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  String _effectivePosterBaseUrl() {
    final base = posterBaseUrl.trim();
    if (base != 'https://joinposter.com') return base;
    final account = posterAccount.trim();
    if (account.isEmpty) return base;
    return 'https://$account.joinposter.com';
  }

  List<dynamic> _unwrapPosterCollection(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      final map = body.cast<String, dynamic>();
      final response = map['response'];
      if (response is List) return response;
      if (response is Map) {
        final data = response['data'];
        if (data is List) return data;
      }
      final data = map['data'];
      if (data is List) return data;
      final result = map['result'];
      if (result is List) return result;
      if (result is Map && result['data'] is List) {
        return result['data'] as List<dynamic>;
      }
    }
    return const [];
  }

  String _posterVal(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int? _posterInt(Map<String, dynamic> row, List<String> keys) {
    final text = _posterVal(row, keys);
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? _posterPrice(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final parsed = _extractPosterPriceValue(row[key]);
      if (parsed != null) return _normalizePosterPrice(parsed);
    }
    final spots = row['spots'];
    if (spots is List) {
      for (final s in spots) {
        if (s is! Map) continue;
        final parsed = _extractPosterPriceValue(s['price']) ??
            _extractPosterPriceValue((s)['profit']);
        if (parsed != null) return _normalizePosterPrice(parsed);
      }
    }
    return null;
  }

  double _normalizePosterPrice(double value) {
    if (value >= 100000 && value % 100 == 0) {
      return value / 100;
    }
    return value;
  }

  double? _extractPosterPriceValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final text = raw.trim().replaceAll(',', '.');
      if (text.isEmpty) return null;
      final parsed = double.tryParse(text);
      if (parsed != null) return parsed;
      final cleaned = text.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return cleaned.isEmpty ? null : double.tryParse(cleaned);
    }
    if (raw is Map) {
      final map = raw.cast<dynamic, dynamic>();
      for (final value in map.values) {
        final parsed = _extractPosterPriceValue(value);
        if (parsed != null) return parsed;
      }
      return null;
    }
    if (raw is List) {
      for (final value in raw) {
        final parsed = _extractPosterPriceValue(value);
        if (parsed != null) return parsed;
      }
      return null;
    }
    return null;
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _hydrateMissingImages(
      Map<String, dynamic> source) async {
    final byName = await _loadAssetImageMap();
    if (byName.isEmpty) return source;
    final categories =
        (source['categories'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
    final nextCategories = <Map<String, dynamic>>[];
    for (final category in categories) {
      final products =
          (category['products'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
      final nextProducts = <Map<String, dynamic>>[];
      for (final product in products) {
        final next = Map<String, dynamic>.from(product);
        final image = (next['image_url'] as String? ?? '').trim();
        if (image.isEmpty) {
          final key = _normalizeMenuKey((next['name'] as String? ?? '').trim());
          final fallback = byName[key];
          if (fallback != null && fallback.isNotEmpty) {
            next['image_url'] = fallback;
          }
        }
        nextProducts.add(next);
      }
      final nextCategory = Map<String, dynamic>.from(category);
      nextCategory['products'] = nextProducts;
      nextCategories.add(nextCategory);
    }
    return {'categories': nextCategories};
  }

  Future<Map<String, String>> _loadAssetImageMap() async {
    if (_assetImageByName != null) return _assetImageByName!;
    final map = <String, String>{};
    try {
      final raw = await rootBundle.loadString('assets/menu_import.csv');
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        _assetImageByName = map;
        return map;
      }
      var headerIndex = 0;
      if (lines.first.trim().toLowerCase() == 'menu_import') {
        headerIndex = 1;
      }
      if (lines.length <= headerIndex + 1) {
        _assetImageByName = map;
        return map;
      }
      final headers = _parseCsvLine(lines[headerIndex]).map(_normalizeHeader);
      final nameIdx = _firstHeaderIndex(headers.toList(), const [
        'name_ru',
        'name',
        'название',
      ]);
      final imageIdx = _firstHeaderIndex(headers.toList(), const [
        'image_url',
        'image',
        'фото',
      ]);
      if (nameIdx < 0 || imageIdx < 0) {
        _assetImageByName = map;
        return map;
      }
      for (var i = headerIndex + 1; i < lines.length; i++) {
        final row = _parseCsvLine(lines[i]);
        if (row.length <= nameIdx || row.length <= imageIdx) continue;
        final name = row[nameIdx].trim();
        final image = row[imageIdx].trim();
        if (name.isEmpty || image.isEmpty) continue;
        map[_normalizeMenuKey(name)] = image;
      }
    } catch (_) {}
    _assetImageByName = map;
    return map;
  }

  String _normalizeMenuKey(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, dynamic> _localizedMenuJson(
      Map<String, dynamic> source, String lang) {
    if (lang == 'ru') return source;
    final localizedCategories = <Map<String, dynamic>>[];
    final categories = source['categories'] as List<dynamic>? ?? [];
    for (final rawCategory in categories) {
      final category = Map<String, dynamic>.from(rawCategory as Map);
      final ruCategoryName = (category['name'] as String? ?? '').trim();
      category['name'] = _translateCategory(ruCategoryName, lang);

      final products = category['products'] as List<dynamic>? ?? [];
      final localizedProducts = <Map<String, dynamic>>[];
      for (final rawProduct in products) {
        final product = Map<String, dynamic>.from(rawProduct as Map);
        final ruProductName = (product['name'] as String? ?? '').trim();
        final ruDescription = (product['description'] as String? ?? '').trim();
        product['name'] = _translateProduct(ruProductName, lang);
        if (ruDescription.isNotEmpty) {
          product['description'] = _translateProduct(ruDescription, lang);
        }
        localizedProducts.add(product);
      }
      category['products'] = localizedProducts;
      localizedCategories.add(category);
    }
    return {'categories': localizedCategories};
  }

  String _translateCategory(String value, String lang) {
    if (value.isEmpty) return value;
    const uzMap = {
      'Напитки': 'Ichimliklar',
      'Роллы': 'Rollar',
      'Суши': 'Sushi',
      'Салаты': 'Salatlar',
      'Сеты': 'Setlar',
      'Соусы': 'Souslar',
      'Запеченные': 'Pishirilganlar',
    };
    const enToUzMap = {
      'Drinks': 'Ichimliklar',
      'Rolls': 'Rollar',
      'Sushi': 'Sushi',
      'Salads': 'Salatlar',
      'Sets': 'Setlar',
      'Sauces': 'Souslar',
      'Baked': 'Pishirilganlar',
      'Mini rolls': 'Mini rolllar',
      'Cold dishes': 'Sovuq taomlar',
      'Fried rolls': 'Qovurilgan rolllar',
      'Kimbap': 'Kimbap',
      'Hot dishes': 'Issiq taomlar',
      'New items': 'Yangi mahsulotlar',
      'Bread': 'Non',
      'Soups': "Sho'rvalar",
      'Desserts': 'Desertlar',
    };
    const enMap = {
      'Напитки': 'Drinks',
      'Роллы': 'Rolls',
      'Суши': 'Sushi',
      'Салаты': 'Salads',
      'Сеты': 'Sets',
      'Соусы': 'Sauces',
      'Запеченные': 'Baked',
    };
    const uzToEnMap = {
      'Ichimliklar': 'Drinks',
      'Rollar': 'Rolls',
      'Rolllar': 'Rolls',
      'Sushi': 'Sushi',
      'Salatlar': 'Salads',
      'Setlar': 'Sets',
      'Souslar': 'Sauces',
      'Pishirilganlar': 'Baked',
      'Mini rolllar': 'Mini rolls',
      'Sovuq taomlar': 'Cold dishes',
      'Qovurilgan rolllar': 'Fried rolls',
      'Kimbap': 'Kimbap',
      'Issiq taomlar': 'Hot dishes',
      'Yangi mahsulotlar': 'New items',
      'Non': 'Bread',
      "Sho'rvalar": 'Soups',
      'Desertlar': 'Desserts',
    };
    if (lang == 'uz') {
      return uzMap[value] ?? enToUzMap[value] ?? _transliterateRu(value);
    }
    if (lang == 'en') {
      return enMap[value] ?? uzToEnMap[value] ?? _transliterateRu(value);
    }
    return value;
  }

  String _translateProduct(String value, String lang) {
    if (value.isEmpty || lang == 'ru') return value;
    if (lang == 'uz') {
      var translated = _replaceTokens(value, _ruToUzTokens);
      translated = _transliterateRu(translated);
      translated = _replaceTokens(translated, _latinToUzTokens);
      return _normalizeSpaces(translated);
    }
    var translated = _replaceTokens(value, _ruToEnTokens);
    translated = _transliterateRu(translated);
    translated = _replaceTokens(translated, _latinToEnTokens);
    return _normalizeSpaces(translated);
  }

  String _normalizeSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _replaceTokens(String input, Map<String, String> tokens) {
    var out = input;
    final entries = tokens.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      final pattern = RegExp(
        r'(?<![A-Za-zА-Яа-яЁё0-9])' +
            RegExp.escape(entry.key) +
            r'(?![A-Za-zА-Яа-яЁё0-9])',
        caseSensitive: false,
        unicode: true,
      );
      out = out.replaceAllMapped(pattern, (m) {
        final found = m.group(0) ?? '';
        if (_isAllUpper(found)) return entry.value.toUpperCase();
        if (_isTitleCase(found)) return _capitalize(entry.value);
        return entry.value;
      });
    }
    return out;
  }

  bool _isAllUpper(String value) {
    if (value.isEmpty) return false;
    return value == value.toUpperCase() && value != value.toLowerCase();
  }

  bool _isTitleCase(String value) {
    if (value.isEmpty) return false;
    final first = value[0];
    return first == first.toUpperCase() && first != first.toLowerCase();
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _transliterateRu(String input) {
    const map = {
      'А': 'A',
      'Б': 'B',
      'В': 'V',
      'Г': 'G',
      'Д': 'D',
      'Е': 'E',
      'Ё': 'Yo',
      'Ж': 'Zh',
      'З': 'Z',
      'И': 'I',
      'Й': 'Y',
      'К': 'K',
      'Л': 'L',
      'М': 'M',
      'Н': 'N',
      'О': 'O',
      'П': 'P',
      'Р': 'R',
      'С': 'S',
      'Т': 'T',
      'У': 'U',
      'Ф': 'F',
      'Х': 'X',
      'Ц': 'Ts',
      'Ч': 'Ch',
      'Ш': 'Sh',
      'Щ': 'Sh',
      'Ъ': '',
      'Ы': 'I',
      'Ь': '',
      'Э': 'E',
      'Ю': 'Yu',
      'Я': 'Ya',
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'yo',
      'ж': 'zh',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'х': 'x',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'sh',
      'ъ': '',
      'ы': 'i',
      'ь': '',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
    };
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      out.write(map[ch] ?? ch);
    }
    return out.toString();
  }

  static const Map<String, String> _ruToUzTokens = {
    r'сок': 'sharbati',
    r'вода': 'suv',
    r'без газа': 'gazsiz',
    r'фанта': 'Fanta',
    r'ролл': 'roll',
    r'роллы': 'rullar',
    r'суши': 'sushi',
    r'салат': 'salat',
    r'соус': 'sous',
    r'острый': 'achchiq',
    r'лосось': 'losos',
    r'креветка': 'krevetka',
    r'краб': 'krab',
    r'курица': 'tovuq',
    r'имбирь': 'imbir',
    r'чесночный': 'sarimsoqli',
    r'кисло-сладкий': 'nordon-shirin',
    r'жаренный': 'qovurilgan',
    r'сет': 'set',
    r'комбо': 'kombo',
    r'шт': 'dona',
    r'гр': 'gr',
    r'мл': 'ml',
    r'л': 'l',
  };

  static const Map<String, String> _ruToEnTokens = {
    r'сок': 'juice',
    r'вода': 'water',
    r'без газа': 'still',
    r'ролл': 'roll',
    r'роллы': 'rolls',
    r'суши': 'sushi',
    r'салат': 'salad',
    r'соус': 'sauce',
    r'острый': 'spicy',
    r'лосось': 'salmon',
    r'креветка': 'shrimp',
    r'краб': 'crab',
    r'курица': 'chicken',
    r'имбирь': 'ginger',
    r'чесночный': 'garlic',
    r'кисло-сладкий': 'sweet-sour',
    r'жаренный': 'fried',
    r'сет': 'set',
    r'комбо': 'combo',
    r'шт': 'pcs',
    r'гр': 'g',
    r'мл': 'ml',
    r'л': 'l',
  };

  static const Map<String, String> _latinToUzTokens = {
    'sok': 'sharbati',
    'voda': 'suv',
    'bez gaza': 'gazsiz',
    'apelsin': 'apelsin',
    'aplesin': 'apelsin',
    'abrikos': 'o‘rik',
    'banan': 'banan',
    'vishnya': 'olcha',
    'persik': 'shaftoli',
  };

  static const Map<String, String> _latinToEnTokens = {
    'sharbati': 'juice',
    'ichimligi': 'drink',
    'ichimlik': 'drink',
    'qovurilgan': 'fried',
    "go'shti": 'beef',
    "go‘shti": 'beef',
    "tovuq": 'chicken',
    'garnir': 'side',
    "sho'rva": 'soup',
    'salat': 'salad',
    'yetkazib': 'delivery',
    'sok': 'juice',
    'apelsin': 'orange',
    'aplesin': 'orange',
    'abrikos': 'apricot',
    'banan': 'banana',
    'vishnya': 'cherry',
    'persik': 'peach',
    'multifrukt': 'multifruit',
    'voda': 'water',
    'bez gaza': 'still',
    'gazsiz': 'still',
    'sous': 'sauce',
    'set': 'set',
    'kombo': 'combo',
    'ostryy': 'spicy',
    'ostriy': 'spicy',
    'ostryi': 'spicy',
    'kurica': 'chicken',
    'krevetka': 'shrimp',
    'krab': 'crab',
    'losos': 'salmon',
    'imbir': 'ginger',
    'chesnochnyy': 'garlic',
    'kislo-sladkiy': 'sweet-sour',
    'sht': 'pcs',
    'gr': 'g',
    'ml': 'ml',
  };

  // ignore: unused_element
  Future<Map<String, dynamic>?> _loadMenuFromAsset(String lang) async {
    try {
      final raw = await rootBundle.loadString('assets/menu_import.csv');
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      int start = 0;
      if (lines.first.trim().toLowerCase() == 'menu_import') start = 1;
      if (lines.length <= start + 1) return null;
      final header = _parseCsvLine(lines[start]);
      if (header.isEmpty) return null;
      final headerNorm = header.map(_normalizeHeader).toList();

      // Supported headers (new multilingual + legacy Russian):
      // name_ru,name_uz,name_en,category_ru,category_uz,category_en,
      // description_ru,description_uz,description_en,price,image_url
      // or: Название,Категория,Цена,Фото
      final nameRuIdx = _firstHeaderIndex(headerNorm, const [
        'name_ru',
        'name',
        'название',
      ]);
      final nameUzIdx = _firstHeaderIndex(headerNorm, const [
        'name_uz',
        'nomi_uz',
      ]);
      final nameEnIdx = _firstHeaderIndex(headerNorm, const [
        'name_en',
      ]);
      final categoryRuIdx = _firstHeaderIndex(headerNorm, const [
        'category_ru',
        'category',
        'категория',
      ]);
      final categoryUzIdx = _firstHeaderIndex(headerNorm, const [
        'category_uz',
      ]);
      final categoryEnIdx = _firstHeaderIndex(headerNorm, const [
        'category_en',
      ]);
      final descriptionRuIdx = _firstHeaderIndex(headerNorm, const [
        'description_ru',
        'description',
        'описание',
      ]);
      final descriptionUzIdx = _firstHeaderIndex(headerNorm, const [
        'description_uz',
      ]);
      final descriptionEnIdx = _firstHeaderIndex(headerNorm, const [
        'description_en',
      ]);
      final priceIdx = _firstHeaderIndex(headerNorm, const [
        'price',
        'цена',
      ]);
      final imageIdx = _firstHeaderIndex(headerNorm, const [
        'image_url',
        'image',
        'фото',
      ]);

      if (nameRuIdx == -1 || categoryRuIdx == -1 || priceIdx == -1) {
        return null;
      }

      final Map<String, List<Map<String, dynamic>>> categoryMap = {};
      int productId = 1;
      for (var i = start + 1; i < lines.length; i++) {
        final row = _parseCsvLine(lines[i]);
        if (row.length <= categoryRuIdx ||
            row.length <= nameRuIdx ||
            row.length <= priceIdx) {
          continue;
        }

        final nameRu = _cell(row, nameRuIdx);
        final nameUz = _cell(row, nameUzIdx);
        final nameEn = _cell(row, nameEnIdx);
        final categoryRu = _cell(row, categoryRuIdx);
        final categoryUz = _cell(row, categoryUzIdx);
        final categoryEn = _cell(row, categoryEnIdx);
        final descriptionRu = _cell(row, descriptionRuIdx);
        final descriptionUz = _cell(row, descriptionUzIdx);
        final descriptionEn = _cell(row, descriptionEnIdx);

        final name = _pickLangValue(lang, ru: nameRu, uz: nameUz, en: nameEn);
        final category = _pickLangValue(lang,
            ru: categoryRu, uz: categoryUz, en: categoryEn);
        final description = _pickLangValue(lang,
            ru: descriptionRu, uz: descriptionUz, en: descriptionEn);
        if (name.isEmpty || category.isEmpty) continue;
        final price = double.tryParse(row[priceIdx].replaceAll(' ', ''));
        final image = _cell(row, imageIdx);
        final product = <String, dynamic>{
          'id': productId++,
          'name': name,
          'description': description.isEmpty ? null : description,
          'price': price ?? 0,
          'image_url': image.isEmpty ? null : image,
          'modifiers': [],
        };
        categoryMap.putIfAbsent(category, () => []).add(product);
      }

      int categoryId = 1;
      final categories = categoryMap.entries.map((e) {
        return <String, dynamic>{
          'id': categoryId++,
          'name': e.key,
          'description': null,
          'products': e.value,
        };
      }).toList();

      return {'categories': categories};
    } catch (e) {
      debugPrint('[menu] asset load failed: $e');
      return null;
    }
  }

  String _cell(List<String> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].trim();
  }

  int _firstHeaderIndex(List<String> headers, List<String> keys) {
    for (final key in keys) {
      final index = headers.indexOf(_normalizeHeader(key));
      if (index >= 0) return index;
    }
    return -1;
  }

  String _normalizeHeader(String raw) {
    return raw.trim().toLowerCase().replaceAll(' ', '_');
  }

  String _pickLangValue(
    String lang, {
    required String ru,
    required String uz,
    required String en,
  }) {
    if (lang == 'uz') {
      if (uz.isNotEmpty) return uz;
      if (ru.isNotEmpty) return ru;
      return en;
    }
    if (lang == 'en') {
      if (en.isNotEmpty) return en;
      if (ru.isNotEmpty) return ru;
      return uz;
    }
    if (ru.isNotEmpty) return ru;
    if (uz.isNotEmpty) return uz;
    return en;
  }

  List<String> _parseCsvLine(String line) {
    final List<String> out = [];
    final buffer = StringBuffer();
    bool inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    out.add(buffer.toString());
    return out;
  }
}
