class ModifierModel {
  final int id;
  final String name;
  final double? price;

  ModifierModel({required this.id, required this.name, this.price});

  factory ModifierModel.fromJson(Map<String, dynamic> json) {
    return ModifierModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble(),
    );
  }
}

class ProductModel {
  final int id;
  final String name;
  final String? description;
  final double? price;
  final double? oldPrice;
  final String? imageUrl;
  final int? categoryId;
  final String? categoryName;
  final bool isActive;
  final bool isDrink;
  final bool isRecommended;
  final bool isPopular;
  final bool isNew;
  final int sortOrder;
  final List<ModifierModel> modifiers;

  ProductModel({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.oldPrice,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
    this.isActive = true,
    this.isDrink = false,
    this.isRecommended = false,
    this.isPopular = false,
    this.isNew = false,
    this.sortOrder = 0,
    required this.modifiers,
  });

  bool get isDiscounted =>
      oldPrice != null && price != null && (oldPrice! > price!);

  int? get discountPercent {
    if (!isDiscounted) return null;
    return (((oldPrice! - price!) / oldPrice!) * 100).round();
  }

  ProductModel copyWith({
    int? id,
    String? name,
    String? description,
    double? price,
    double? oldPrice,
    String? imageUrl,
    int? categoryId,
    String? categoryName,
    bool? isActive,
    bool? isDrink,
    bool? isRecommended,
    bool? isPopular,
    bool? isNew,
    int? sortOrder,
    List<ModifierModel>? modifiers,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      oldPrice: oldPrice ?? this.oldPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      isActive: isActive ?? this.isActive,
      isDrink: isDrink ?? this.isDrink,
      isRecommended: isRecommended ?? this.isRecommended,
      isPopular: isPopular ?? this.isPopular,
      isNew: isNew ?? this.isNew,
      sortOrder: sortOrder ?? this.sortOrder,
      modifiers: modifiers ?? this.modifiers,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final mods = (json['modifiers'] as List<dynamic>? ?? [])
        .map((e) => ModifierModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return ProductModel(
      id: json['id'] as int,
      name: json['title'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      oldPrice: (json['oldPrice'] as num?)?.toDouble() ??
          (json['old_price'] as num?)?.toDouble(),
      imageUrl: json['imageUrl'] as String? ?? json['image_url'] as String?,
      categoryId: json['categoryId'] as int? ?? json['category_id'] as int?,
      categoryName:
          json['categoryName'] as String? ?? json['category_name'] as String?,
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      isDrink: json['isDrink'] as bool? ?? json['is_drink'] as bool? ?? false,
      isRecommended: json['isRecommended'] as bool? ??
          json['is_recommended'] as bool? ??
          false,
      isPopular:
          json['isPopular'] as bool? ?? json['is_popular'] as bool? ?? false,
      isNew: json['isNew'] as bool? ?? json['is_new'] as bool? ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ??
          (json['sort_order'] as num?)?.toInt() ??
          0,
      modifiers: mods,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': name,
        'name': name,
        'description': description,
        'price': price,
        'oldPrice': oldPrice,
        'old_price': oldPrice,
        'imageUrl': imageUrl,
        'image_url': imageUrl,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'isActive': isActive,
        'isDrink': isDrink,
        'isRecommended': isRecommended,
        'isPopular': isPopular,
        'isNew': isNew,
        'sortOrder': sortOrder,
        'modifiers': modifiers
            .map((m) => {'id': m.id, 'name': m.name, 'price': m.price})
            .toList(),
      };
}

class CategoryModel {
  final int id;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final List<ProductModel> products;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
    required this.products,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    final prods = (json['products'] as List<dynamic>? ?? [])
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return CategoryModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ??
          (json['sort_order'] as num?)?.toInt() ??
          0,
      products: prods,
    );
  }
}

class MenuResponse {
  final List<CategoryModel> categories;

  MenuResponse({required this.categories});

  factory MenuResponse.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as List<dynamic>? ?? [])
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return MenuResponse(categories: cats);
  }
}
