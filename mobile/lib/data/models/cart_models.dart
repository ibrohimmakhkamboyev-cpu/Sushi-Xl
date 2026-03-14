import 'menu_models.dart';

class CartModifierSelection {
  final int modifierId;
  final double price;

  CartModifierSelection({required this.modifierId, required this.price});

  Map<String, dynamic> toJson() => {
        'modifier_id': modifierId,
        'price': price,
      };
}

class CartItemModel {
  final ProductModel product;
  int qty;
  final List<CartModifierSelection> modifiers;

  CartItemModel({required this.product, this.qty = 1, required this.modifiers});

  int get productId => product.id;
  String get title => product.name;
  double get unitPrice => product.price ?? 0;
  double? get oldPrice => product.oldPrice;

  double total() {
    final base = unitPrice * qty;
    final mods = modifiers.fold<double>(0, (sum, m) => sum + m.price) * qty;
    return base + mods;
  }
}
