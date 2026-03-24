import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../services/telegram_notifier.dart';
import '../config.dart';
import '../../data/repositories/menu_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/address_repository.dart';
import '../../data/repositories/public_repository.dart';
import '../../data/repositories/order_history_repository.dart';
import '../../data/models/menu_models.dart';
import '../../data/models/order_models.dart';
import '../../data/models/order_history_models.dart';
import '../../data/models/order_detail_models.dart';
import '../../data/models/address_models.dart';
import '../../data/models/cart_models.dart';
import '../cache/cart_cache.dart';
import '../cache/favorites_cache.dart';
import '../cache/mailing_cache.dart';
import '../cache/admin_panel_cache.dart';
import '../cache/order_history_cache.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final dioProvider = Provider<Dio>((ref) {
  final dio = ref.read(apiClientProvider).client;
  dio.interceptors
      .removeWhere((interceptor) => interceptor is _UserAuthInterceptor);
  dio.interceptors.add(_UserAuthInterceptor(ref));
  return dio;
});

final menuRepositoryProvider =
    Provider((ref) => MenuRepository(ref.read(dioProvider)));
final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.read(dioProvider)));
final orderRepositoryProvider =
    Provider((ref) => OrderRepository(ref.read(dioProvider)));
final addressRepositoryProvider =
    Provider((ref) => AddressRepository(ref.read(dioProvider)));
final publicRepositoryProvider =
    Provider((ref) => PublicRepository(ref.read(dioProvider)));
final orderHistoryRepositoryProvider =
    Provider((ref) => OrderHistoryRepository(ref.read(dioProvider)));
final telegramNotifierProvider = Provider<TelegramNotifier>(
  (ref) => TelegramNotifier(
    dio: ref.read(dioProvider),
    botToken: telegramBotToken,
    chatId: telegramGroupId,
  ),
);

final localeProvider = StateProvider<Locale>((ref) => const Locale('ru'));

final menuProvider = FutureProvider((ref) async {
  final locale = ref.watch(localeProvider);
  return ref.read(menuRepositoryProvider).fetchMenu(locale.languageCode);
});

class UserSession {
  final int userId;
  final String phone;
  final String fullName;
  final String preferredLang;
  final String gender;
  final String accessToken;

  UserSession({
    required this.userId,
    required this.phone,
    required this.fullName,
    required this.preferredLang,
    this.gender = '',
    this.accessToken = '',
  });

  factory UserSession.guest({String preferredLang = 'ru'}) => UserSession(
        userId: 0,
        phone: '',
        fullName: '',
        preferredLang: preferredLang,
        gender: '',
        accessToken: '',
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'phone': phone,
        'full_name': fullName,
        'preferred_lang': preferredLang,
        'gender': gender,
        'access_token': accessToken,
      };

  static UserSession fromJson(Map<String, dynamic> json) => UserSession(
        userId: json['user_id'] as int,
        phone: json['phone'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        preferredLang: json['preferred_lang'] as String? ?? 'ru',
        gender: json['gender'] as String? ?? '',
        accessToken: json['access_token'] as String? ?? '',
      );
}

class _UserAuthInterceptor extends Interceptor {
  final Ref _ref;
  _UserAuthInterceptor(this._ref);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = _ref.read(userSessionProvider);
    final token = (session?.accessToken ?? '').trim();
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

final userSessionProvider =
    StateProvider<UserSession?>((ref) => UserSession.guest());
final profilePhotoProvider = StateProvider<String?>((ref) => null);

class DeliveryLocation {
  final String address;
  final double lat;
  final double lng;
  const DeliveryLocation(
      {required this.address, required this.lat, required this.lng});
}

final deliveryLocationProvider =
    StateProvider<DeliveryLocation?>((ref) => null);

final loginRequiredProvider = Provider<bool>((ref) {
  return ref.watch(userSessionProvider) == null;
});

class CartState {
  final List<CartItemModel> items;
  final String paymentMethod;
  final String deliveryType;

  CartState({
    required this.items,
    required this.paymentMethod,
    required this.deliveryType,
  });

  CartState copyWith({
    List<CartItemModel>? items,
    String? paymentMethod,
    String? deliveryType,
  }) {
    return CartState(
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      deliveryType: deliveryType ?? this.deliveryType,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final CartCache _cache = CartCache();
  final Ref _ref;

  CartNotifier(this._ref)
      : super(
          CartState(
            items: [],
            paymentMethod: 'cash',
            deliveryType: 'delivery',
          ),
        );

  void add(ProductModel product,
      {List<CartModifierSelection> modifiers = const []}) {
    final snapshot = product.copyWith(
      price: product.price,
      oldPrice: product.oldPrice,
    );
    final existing = state.items
        .where((e) =>
            e.product.id == product.id &&
            _modsKey(e.modifiers) == _modsKey(modifiers))
        .toList();
    if (existing.isNotEmpty) {
      existing.first.qty += 1;
      state = state.copyWith(items: [...state.items]);
      _persist();
      return;
    }
    state = state.copyWith(items: [
      ...state.items,
      CartItemModel(product: snapshot, modifiers: modifiers)
    ]);
    _persist();
  }

  void remove(ProductModel product) {
    state = state.copyWith(
        items: state.items.where((e) => e.product.id != product.id).toList());
    _persist();
  }

  void removeItem(ProductModel product,
      {List<CartModifierSelection> modifiers = const []}) {
    state = state.copyWith(
      items: state.items
          .where((e) => !(e.product.id == product.id &&
              _modsKey(e.modifiers) == _modsKey(modifiers)))
          .toList(),
    );
    _persist();
  }

  void updateQty(ProductModel product, int qty,
      {List<CartModifierSelection> modifiers = const []}) {
    final items = [...state.items];
    for (final item in items) {
      if (item.product.id == product.id &&
          _modsKey(item.modifiers) == _modsKey(modifiers)) {
        item.qty = qty;
      }
    }
    state = state.copyWith(items: items);
    _persist();
  }

  void setPaymentMethod(String value) {
    state = state.copyWith(paymentMethod: value);
    _persist();
  }

  void setDeliveryType(String value) {
    state = state.copyWith(deliveryType: value);
    _persist();
  }

  void setFromOrder(List<CartItemModel> items) {
    state = state.copyWith(items: items);
    _persist();
  }

  double total() {
    double sum = 0;
    for (final item in state.items) {
      sum += item.total();
    }
    return sum;
  }

  Future<void> _persist() async {
    final json = {
      'payment_method': state.paymentMethod,
      'delivery_type': state.deliveryType,
      'items': state.items
          .map((e) => {
                'product': {
                  'id': e.product.id,
                  'name': e.product.name,
                  'description': e.product.description,
                  'price': e.product.price,
                  'old_price': e.product.oldPrice,
                  'image_url': e.product.imageUrl,
                  'category_id': e.product.categoryId,
                  'category_name': e.product.categoryName,
                  'is_active': e.product.isActive,
                  'is_drink': e.product.isDrink,
                  'modifiers': e.product.modifiers
                      .map(
                          (m) => {'id': m.id, 'name': m.name, 'price': m.price})
                      .toList(),
                },
                'qty': e.qty,
                'modifiers': e.modifiers.map((m) => m.toJson()).toList(),
              })
          .toList(),
    };
    await _cache.save(json, scope: _cartScope());
  }

  Future<void> loadFromCache() async {
    final data = await _cache.load(scope: _cartScope());
    if (data == null) {
      state = state
          .copyWith(items: [], paymentMethod: 'cash', deliveryType: 'delivery');
      return;
    }
    final items = (data['items'] as List<dynamic>? ?? []).map((e) {
      final map = e as Map<String, dynamic>;
      final p = map['product'] as Map<String, dynamic>;
      final product = ProductModel.fromJson(p);
      final mods = (map['modifiers'] as List<dynamic>? ?? []).map((m) {
        final mm = m as Map<String, dynamic>;
        return CartModifierSelection(
          modifierId: mm['modifier_id'] as int,
          price: (mm['price'] as num).toDouble(),
        );
      }).toList();
      return CartItemModel(
          product: product, qty: map['qty'] as int? ?? 1, modifiers: mods);
    }).toList();
    state = state.copyWith(
      items: items,
      paymentMethod: data['payment_method'] as String? ?? 'cash',
      deliveryType: data['delivery_type'] as String? ?? 'delivery',
    );
  }

  Future<void> clear() async {
    await _cache.clear(scope: _cartScope());
    state = state
        .copyWith(items: [], paymentMethod: 'cash', deliveryType: 'delivery');
  }

  String _cartScope() {
    final session = _ref.read(userSessionProvider);
    if (session == null) return 'guest';
    final phone =
        session.phone.trim().isEmpty ? 'no_phone' : session.phone.trim();
    if (session.userId > 0) return 'uid_${session.userId}';
    return 'phone_$phone';
  }

  String _modsKey(List<CartModifierSelection> mods) {
    return mods.map((e) => '${e.modifierId}:${e.price}').join('|');
  }
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier(ref));

class FavoritesNotifier extends StateNotifier<Set<int>> {
  final FavoritesCache _cache = FavoritesCache();
  final Ref _ref;
  FavoritesNotifier(this._ref) : super(<int>{});

  bool contains(int id) => state.contains(id);

  Future<void> loadFromCache() async {
    final scope = _scope();
    if (scope == null) {
      state = <int>{};
      return;
    }
    final ids = await _cache.load(scope: scope);
    state = ids.toSet();
  }

  Future<void> toggle(int id) async {
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    final scope = _scope();
    if (scope != null) {
      await _cache.save(next.toList(), scope: scope);
    }
  }

  Future<void> clear() async {
    final scope = _scope();
    if (scope != null) {
      await _cache.clear(scope: scope);
    }
    state = <int>{};
  }

  String? _scope() {
    final session = _ref.read(userSessionProvider);
    if (session == null) return null;
    if (session.userId > 0) return 'uid_${session.userId}';
    final phone = session.phone.trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    return null;
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<int>>(
    (ref) => FavoritesNotifier(ref));

class LocalOrderEntry {
  final int id;
  final String status;
  final String paymentStatus;
  final String? posterOrderId;
  final String createdAt;
  final List<OrderDetailItem> items;

  const LocalOrderEntry({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.posterOrderId,
    required this.createdAt,
    required this.items,
  });

  OrderHistoryItem toHistoryItem() {
    return OrderHistoryItem(
      id: id,
      status: status,
      paymentStatus: paymentStatus,
      posterOrderId: posterOrderId,
      createdAt: createdAt,
    );
  }

  OrderDetailResponse toDetail() => OrderDetailResponse(id: id, items: items);

  OrderResponse toOrder() =>
      OrderResponse(id: id, status: status, paymentStatus: paymentStatus);

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'payment_status': paymentStatus,
        'poster_order_id': posterOrderId,
        'created_at': createdAt,
        'items': items
            .map((e) => {
                  'product_id': e.productId,
                  'qty': e.qty,
                  'price': e.price,
                  'modifiers': e.modifiers
                      .map((m) =>
                          {'modifier_id': m.modifierId, 'price': m.price})
                      .toList(),
                })
            .toList(),
      };

  factory LocalOrderEntry.fromJson(Map<String, dynamic> json) {
    final rows = (json['items'] as List<dynamic>? ?? const <dynamic>[]);
    final parsedItems = rows.map((raw) {
      final item = raw as Map<String, dynamic>;
      final modRows =
          (item['modifiers'] as List<dynamic>? ?? const <dynamic>[]);
      final mods = modRows.map((m) {
        final mm = m as Map<String, dynamic>;
        return OrderDetailModifier(
          modifierId: mm['modifier_id'] as int? ?? 0,
          price: (mm['price'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      return OrderDetailItem(
        productId: item['product_id'] as int? ?? 0,
        qty: item['qty'] as int? ?? 1,
        price: (item['price'] as num?)?.toDouble() ?? 0,
        modifiers: mods,
      );
    }).toList();

    return LocalOrderEntry(
      id: json['id'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      posterOrderId: json['poster_order_id'] as String?,
      createdAt:
          json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      items: parsedItems,
    );
  }
}

class LocalOrderHistoryNotifier extends StateNotifier<List<LocalOrderEntry>> {
  final Ref _ref;
  final OrderHistoryCache _cache = OrderHistoryCache();

  LocalOrderHistoryNotifier(this._ref) : super(const <LocalOrderEntry>[]);

  Future<void> loadFromCache() async {
    final scope = _scope();
    if (scope == null) {
      state = const <LocalOrderEntry>[];
      return;
    }
    final rows = await _cache.load(scope: scope);
    final loaded = rows.map(LocalOrderEntry.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = loaded;
  }

  Future<void> addOrderFromCart({
    required int orderId,
    required String status,
    required String paymentStatus,
    String? posterOrderId,
    required DateTime createdAt,
    required List<CartItemModel> cartItems,
  }) async {
    final detailItems = cartItems
        .map((item) => OrderDetailItem(
              productId: item.product.id,
              qty: item.qty,
              price: item.unitPrice,
              modifiers: item.modifiers
                  .map((m) => OrderDetailModifier(
                        modifierId: m.modifierId,
                        price: m.price,
                      ))
                  .toList(),
            ))
        .toList();
    final entry = LocalOrderEntry(
      id: orderId,
      status: status,
      paymentStatus: paymentStatus,
      posterOrderId: posterOrderId,
      createdAt: createdAt.toIso8601String(),
      items: detailItems,
    );
    state = [
      entry,
      ...state.where((e) => e.id != orderId),
    ];
    await _persist();
  }

  OrderResponse? findOrder(int orderId) {
    for (final item in state) {
      if (item.id == orderId) return item.toOrder();
    }
    return null;
  }

  OrderDetailResponse? findDetail(int orderId) {
    for (final item in state) {
      if (item.id == orderId) return item.toDetail();
    }
    return null;
  }

  Future<void> clear() async {
    final scope = _scope();
    if (scope != null) {
      await _cache.clear(scope: scope);
    }
    state = const <LocalOrderEntry>[];
  }

  Future<void> _persist() async {
    final scope = _scope();
    if (scope == null) return;
    await _cache.save(state.map((e) => e.toJson()).toList(), scope: scope);
  }

  String? _scope() {
    final session = _ref.read(userSessionProvider);
    if (session == null) return null;
    if (session.userId > 0) return 'uid_${session.userId}';
    final phone = session.phone.trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    return 'local_user';
  }
}

final localOrderHistoryProvider =
    StateNotifierProvider<LocalOrderHistoryNotifier, List<LocalOrderEntry>>(
        (ref) => LocalOrderHistoryNotifier(ref));

final orderSubmitProvider =
    FutureProvider.family<OrderResponse, int>((ref, userId) async {
  if (!useBackend) {
    return OrderResponse(
      id: DateTime.now().millisecondsSinceEpoch,
      status: 'telegram_only',
      paymentStatus: 'pending',
    );
  }
  final cart = ref.read(cartProvider);
  final items = cart.items
      .map(
        (e) => OrderItemIn(
          productId: e.product.id,
          qty: e.qty,
          price: e.unitPrice,
          oldPrice: e.oldPrice,
          title: e.title,
          notes: null,
          modifiers: e.modifiers
              .map((m) => OrderItemModifierIn(
                    modifierId: m.modifierId,
                    price: m.price,
                  ))
              .toList(),
        ),
      )
      .toList();
  final request = CreateOrderRequest(
    userId: userId,
    items: items,
    deliveryType: cart.deliveryType,
    addressId: null,
    scheduledAt: null,
    notes: null,
    paymentMethod: cart.paymentMethod,
  );
  return ref.read(orderRepositoryProvider).createOrder(request);
});

final orderFetchProvider =
    FutureProvider.family<OrderResponse, int>((ref, orderId) async {
  if (!useBackend) {
    final entries = ref.watch(localOrderHistoryProvider);
    for (final entry in entries) {
      if (entry.id == orderId) return entry.toOrder();
    }
    return OrderResponse(
        id: orderId, status: 'telegram_only', paymentStatus: 'pending');
  }
  return ref.read(orderRepositoryProvider).getOrder(orderId);
});

final addressesProvider =
    FutureProvider.family<List<AddressModel>, int>((ref, userId) async {
  if (!useBackend || userId <= 0) return const <AddressModel>[];
  return ref.read(addressRepositoryProvider).listAddresses(userId);
});

final workingHoursProvider = FutureProvider((ref) async {
  if (!useBackend) return null;
  return ref.read(publicRepositoryProvider).getWorkingHours();
});

final orderHistoryProvider =
    FutureProvider.family<List<OrderHistoryItem>, int>((ref, userId) async {
  if (!useBackend || userId <= 0) {
    final entries = ref.watch(localOrderHistoryProvider);
    return entries.map((e) => e.toHistoryItem()).toList();
  }
  return ref.read(orderHistoryRepositoryProvider).list(userId);
});

final orderDetailProvider =
    FutureProvider.family<OrderDetailResponse, int>((ref, orderId) async {
  if (!useBackend) {
    final detail =
        ref.read(localOrderHistoryProvider.notifier).findDetail(orderId);
    return detail ??
        OrderDetailResponse(id: orderId, items: const <OrderDetailItem>[]);
  }
  return ref.read(orderHistoryRepositoryProvider).detail(orderId);
});

class MailingItem {
  final int id;
  final String title;
  final String message;
  final String image;
  final DateTime createdAt;

  const MailingItem({
    required this.id,
    required this.title,
    this.message = '',
    required this.image,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'image': image,
        'created_at': createdAt.toIso8601String(),
      };

  factory MailingItem.fromJson(Map<String, dynamic> json) => MailingItem(
        id: json['id'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        image: json['image'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class MailingState {
  final List<MailingItem> items;
  final int? lastSeenId;
  final Set<int> hiddenIds;

  const MailingState({
    required this.items,
    required this.lastSeenId,
    this.hiddenIds = const <int>{},
  });

  List<MailingItem> get visibleItems =>
      items.where((e) => !hiddenIds.contains(e.id)).toList(growable: false);

  bool get hasUnread =>
      visibleItems.isNotEmpty && lastSeenId != visibleItems.first.id;

  MailingState copyWith({
    List<MailingItem>? items,
    int? lastSeenId,
    Set<int>? hiddenIds,
    bool clearSeen = false,
  }) {
    return MailingState(
      items: items ?? this.items,
      lastSeenId: clearSeen ? null : (lastSeenId ?? this.lastSeenId),
      hiddenIds: hiddenIds ?? this.hiddenIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'last_seen_id': lastSeenId,
        'hidden_ids': hiddenIds.toList(),
      };

  factory MailingState.fromJson(Map<String, dynamic> json) {
    final rows = (json['items'] as List<dynamic>? ?? []);
    final items = rows
        .whereType<Map<String, dynamic>>()
        .map(MailingItem.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final hiddenIds = (json['hidden_ids'] as List<dynamic>? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();
    return MailingState(
      items: items,
      lastSeenId: json['last_seen_id'] as int?,
      hiddenIds: hiddenIds,
    );
  }
}

class MailingNotifier extends StateNotifier<MailingState> {
  final MailingCache _cache = MailingCache();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSub;

  MailingNotifier()
      : super(const MailingState(items: <MailingItem>[], lastSeenId: null)) {
    _startRemoteSync();
  }

  Future<void> loadFromCache() async {
    final raw = await _cache.load();
    if (raw != null) {
      state = MailingState.fromJson(raw);
    }
    await _persist();
  }

  Future<void> send({
    required String title,
    required String image,
    String message = '',
    bool publishRemote = true,
  }) async {
    final item = MailingItem(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      message: message,
      image: image,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(items: _mergeItems([item, ...state.items]));
    await _persist();

    if (!publishRemote || Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('mailings')
          .doc('${item.id}')
          .set({
        'id': item.id,
        'title': item.title,
        'message': item.message,
        'image': item.image,
        'created_at': FieldValue.serverTimestamp(),
        'created_at_ms': item.id,
      });
    } catch (e) {
      debugPrint('[mailings] cloud publish failed: $e');
    }
  }

  Future<void> markAllSeen({List<MailingItem> externalItems = const []}) async {
    final mergedVisible = _mergeItems([
      ...state.visibleItems,
      ...externalItems.where((item) => !state.hiddenIds.contains(item.id)),
    ]);
    final topId = mergedVisible.isEmpty ? null : mergedVisible.first.id;
    state = state.copyWith(lastSeenId: topId, clearSeen: mergedVisible.isEmpty);
    await _persist();
  }

  Future<void> remove(int id) async {
    final hiddenIds = <int>{...state.hiddenIds, id};
    final visible = state.visibleItems.where((e) => e.id != id).toList();
    int? seen = state.lastSeenId;
    if (seen != null && !visible.any((e) => e.id == seen)) {
      seen = visible.isEmpty ? null : visible.first.id;
    }
    state = state.copyWith(
      hiddenIds: hiddenIds,
      lastSeenId: seen,
      clearSeen: visible.isEmpty,
    );
    await _persist();
  }

  List<MailingItem> _mergeItems(List<MailingItem> source) {
    final byId = <int, MailingItem>{};
    for (final item in source) {
      final current = byId[item.id];
      if (current == null || item.createdAt.isAfter(current.createdAt)) {
        byId[item.id] = item;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  MailingItem _fromRemoteDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAtRaw = data['created_at'];
    final createdAtMs = (data['created_at_ms'] as num?)?.toInt();
    DateTime createdAt = DateTime.now();
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtMs != null) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    }
    return MailingItem(
      id: (data['id'] as num?)?.toInt() ?? doc.id.hashCode,
      title: (data['title'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      image: (data['image'] as String? ?? '').trim(),
      createdAt: createdAt,
    );
  }

  void _startRemoteSync() {
    if (Firebase.apps.isEmpty) {
      debugPrint('[mailings] firebase unavailable, cloud sync disabled');
      return;
    }
    try {
      _remoteSub = FirebaseFirestore.instance
          .collection('mailings')
          .orderBy('created_at_ms', descending: true)
          .limit(100)
          .snapshots()
          .listen(
        (snapshot) async {
          final remoteItems = snapshot.docs.map(_fromRemoteDoc).toList();
          state = state.copyWith(
              items: _mergeItems([...remoteItems, ...state.items]));
          await _persist();
        },
        onError: (Object e) {
          debugPrint('[mailings] cloud sync error: $e');
        },
      );
    } catch (e) {
      debugPrint('[mailings] cloud sync unavailable: $e');
    }
  }

  Future<void> _persist() async {
    await _cache.save(state.toJson());
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    super.dispose();
  }
}

final mailingProvider = StateNotifierProvider<MailingNotifier, MailingState>(
    (ref) => MailingNotifier());

final backendMailingsProvider = FutureProvider<List<MailingItem>>((ref) async {
  if (!useBackend) return const <MailingItem>[];
  final locale = ref.watch(localeProvider);
  try {
    final rows = await ref
        .read(publicRepositoryProvider)
        .getNotifications(lang: locale.languageCode);
    return rows.map((row) {
      final parsed = DateTime.tryParse(row.createdAt);
      return MailingItem(
        id: row.id,
        title: row.title,
        message: row.message,
        image: row.imageUrl,
        createdAt: parsed ?? DateTime.now(),
      );
    }).toList();
  } catch (_) {
    return const <MailingItem>[];
  }
});

class AdminAdItem {
  final int id;
  final String title;
  final String subtitle;
  final String image;
  final String actionType;
  final int? productId;
  final int? categoryId;
  final List<int> productIds;
  final String? targetUrl;
  final int sortOrder;

  const AdminAdItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.actionType,
    required this.productId,
    required this.categoryId,
    required this.targetUrl,
    required this.sortOrder,
    this.productIds = const [],
  });

  factory AdminAdItem.fromPublicBanner(PublicBannerDto row) {
    return AdminAdItem(
      id: row.id,
      title: row.title.trim(),
      subtitle: row.subtitle.trim(),
      image: row.imageUrl.trim(),
      actionType: row.actionType.trim().toLowerCase(),
      productId: row.productId,
      categoryId: row.categoryId,
      productIds: row.linkedProductIds,
      targetUrl: row.targetUrl?.trim().isNotEmpty == true
          ? row.targetUrl?.trim()
          : null,
      sortOrder: row.sortOrder,
    );
  }

  AdminAdItem copyWith({
    int? id,
    String? title,
    String? subtitle,
    String? image,
    String? actionType,
    int? productId,
    int? categoryId,
    List<int>? productIds,
    String? targetUrl,
    int? sortOrder,
  }) {
    return AdminAdItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      image: image ?? this.image,
      actionType: actionType ?? this.actionType,
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      productIds: productIds ?? this.productIds,
      targetUrl: targetUrl ?? this.targetUrl,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'image': image,
        'action_type': actionType,
        'product_id': productId,
        'category_id': categoryId,
        'product_ids': productIds,
        'target_url': targetUrl,
        'sort_order': sortOrder,
      };
}

final adminAdsProvider = FutureProvider<List<AdminAdItem>>((ref) async {
  final locale = ref.watch(localeProvider);
  try {
    final remote = await ref
        .read(publicRepositoryProvider)
        .getBanners(lang: locale.languageCode);
    final mapped = remote
        .where((banner) => banner.isActive && banner.imageUrl.trim().isNotEmpty)
        .map(AdminAdItem.fromPublicBanner)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return mapped;
  } catch (_) {
    return const <AdminAdItem>[];
  }
});

class SupportFaqItem {
  final String id;
  final String question;
  final String answer;

  const SupportFaqItem({
    required this.id,
    required this.question,
    required this.answer,
  });

  SupportFaqItem copyWith({
    String? id,
    String? question,
    String? answer,
  }) {
    return SupportFaqItem(
      id: id ?? this.id,
      question: question ?? this.question,
      answer: answer ?? this.answer,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'answer': answer,
      };

  factory SupportFaqItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return SupportFaqItem(
      id: (json['id'] as String? ?? '$now').trim(),
      question: (json['question'] as String? ?? '').trim(),
      answer: (json['answer'] as String? ?? '').trim(),
    );
  }
}

class SupportCenterConfig {
  final String langCode;
  final String phoneNumber;
  final List<SupportFaqItem> faqs;
  final String callLabel;
  final String chatLabel;
  final String chatSubtitle;
  final String chatIntro;

  const SupportCenterConfig({
    required this.langCode,
    required this.phoneNumber,
    required this.faqs,
    required this.callLabel,
    required this.chatLabel,
    required this.chatSubtitle,
    required this.chatIntro,
  });

  SupportCenterConfig copyWith({
    String? langCode,
    String? phoneNumber,
    List<SupportFaqItem>? faqs,
    String? callLabel,
    String? chatLabel,
    String? chatSubtitle,
    String? chatIntro,
  }) {
    return SupportCenterConfig(
      langCode: langCode ?? this.langCode,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      faqs: faqs ?? this.faqs,
      callLabel: callLabel ?? this.callLabel,
      chatLabel: chatLabel ?? this.chatLabel,
      chatSubtitle: chatSubtitle ?? this.chatSubtitle,
      chatIntro: chatIntro ?? this.chatIntro,
    );
  }

  Map<String, dynamic> toJson() => {
        'lang_code': langCode,
        'phone_number': phoneNumber,
        'faqs': faqs.map((e) => e.toJson()).toList(),
        'call_label': callLabel,
        'chat_label': chatLabel,
        'chat_subtitle': chatSubtitle,
        'chat_intro': chatIntro,
      };

  factory SupportCenterConfig.fromJson(
    Map<String, dynamic> json, {
    String fallbackLang = 'ru',
  }) {
    final rawFaqs = (json['faqs'] as List<dynamic>? ?? const []);
    final faqs = rawFaqs
        .whereType<Map>()
        .map((e) => SupportFaqItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.question.isNotEmpty && e.answer.isNotEmpty)
        .toList();
    final defaults = defaultSupportCenterConfig(fallbackLang);
    final cachedLang = (json['lang_code'] as String? ?? '').trim();
    final sameLang = cachedLang == fallbackLang;
    return SupportCenterConfig(
      langCode: fallbackLang,
      phoneNumber:
          (json['phone_number'] as String? ?? defaults.phoneNumber).trim(),
      faqs: sameLang && faqs.isNotEmpty ? faqs : defaults.faqs,
      callLabel: sameLang
          ? (json['call_label'] as String? ?? defaults.callLabel).trim()
          : defaults.callLabel,
      chatLabel: sameLang
          ? (json['chat_label'] as String? ?? defaults.chatLabel).trim()
          : defaults.chatLabel,
      chatSubtitle: sameLang
          ? (json['chat_subtitle'] as String? ?? defaults.chatSubtitle).trim()
          : defaults.chatSubtitle,
      chatIntro: sameLang
          ? (json['chat_intro'] as String? ?? defaults.chatIntro).trim()
          : defaults.chatIntro,
    );
  }
}

class SupportChatMessage {
  final String id;
  final String threadId;
  final String text;
  final String sender;
  final String senderLabel;
  final int createdAtMs;
  final String faqId;

  const SupportChatMessage({
    required this.id,
    required this.threadId,
    required this.text,
    required this.sender,
    required this.senderLabel,
    required this.createdAtMs,
    this.faqId = '',
  });

  SupportChatMessage copyWith({
    String? id,
    String? threadId,
    String? text,
    String? sender,
    String? senderLabel,
    int? createdAtMs,
    String? faqId,
  }) {
    return SupportChatMessage(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      senderLabel: senderLabel ?? this.senderLabel,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      faqId: faqId ?? this.faqId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'thread_id': threadId,
        'text': text,
        'sender': sender,
        'sender_label': senderLabel,
        'created_at_ms': createdAtMs,
        'faq_id': faqId,
      };

  Map<String, dynamic> toRemoteJson() => {
        'text': text,
        'sender': sender,
        'sender_label': senderLabel,
        'created_at_ms': createdAtMs,
        'created_at': FieldValue.serverTimestamp(),
        if (faqId.isNotEmpty) 'faq_id': faqId,
      };

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAtMs = (json['created_at_ms'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return SupportChatMessage(
      id: (json['id'] as String? ?? '$createdAtMs').trim(),
      threadId: (json['thread_id'] as String? ?? '').trim(),
      text: (json['text'] as String? ?? '').trim(),
      sender: (json['sender'] as String? ?? 'bot').trim(),
      senderLabel: (json['sender_label'] as String? ?? '').trim(),
      createdAtMs: createdAtMs,
      faqId: (json['faq_id'] as String? ?? '').trim(),
    );
  }

  factory SupportChatMessage.fromDocument(
    String threadId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return SupportChatMessage(
      id: doc.id,
      threadId: threadId,
      text: (data['text'] as String? ?? '').trim(),
      sender: (data['sender'] as String? ?? 'bot').trim(),
      senderLabel: (data['sender_label'] as String? ?? '').trim(),
      createdAtMs: (data['created_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      faqId: (data['faq_id'] as String? ?? '').trim(),
    );
  }
}

class SupportChatThread {
  final String threadId;
  final String customerName;
  final String customerPhone;
  final String customerLang;
  final String lastMessage;
  final String lastSender;
  final String lastCustomerMessage;
  final int updatedAtMs;
  final bool needsAdmin;
  final bool answeredByApp;

  const SupportChatThread({
    required this.threadId,
    required this.customerName,
    required this.customerPhone,
    required this.customerLang,
    required this.lastMessage,
    required this.lastSender,
    required this.lastCustomerMessage,
    required this.updatedAtMs,
    required this.needsAdmin,
    required this.answeredByApp,
  });

  SupportChatThread copyWith({
    String? threadId,
    String? customerName,
    String? customerPhone,
    String? customerLang,
    String? lastMessage,
    String? lastSender,
    String? lastCustomerMessage,
    int? updatedAtMs,
    bool? needsAdmin,
    bool? answeredByApp,
  }) {
    return SupportChatThread(
      threadId: threadId ?? this.threadId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerLang: customerLang ?? this.customerLang,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSender: lastSender ?? this.lastSender,
      lastCustomerMessage: lastCustomerMessage ?? this.lastCustomerMessage,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      needsAdmin: needsAdmin ?? this.needsAdmin,
      answeredByApp: answeredByApp ?? this.answeredByApp,
    );
  }

  Map<String, dynamic> toJson() => {
        'thread_id': threadId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_lang': customerLang,
        'last_message': lastMessage,
        'last_sender': lastSender,
        'last_customer_message': lastCustomerMessage,
        'updated_at_ms': updatedAtMs,
        'needs_admin': needsAdmin,
        'answered_by_app': answeredByApp,
      };

  Map<String, dynamic> toRemoteJson() => {
        'thread_id': threadId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_lang': customerLang,
        'last_message': lastMessage,
        'last_sender': lastSender,
        'last_customer_message': lastCustomerMessage,
        'updated_at_ms': updatedAtMs,
        'updated_at': FieldValue.serverTimestamp(),
        'needs_admin': needsAdmin,
        'answered_by_app': answeredByApp,
      };

  factory SupportChatThread.fromJson(Map<String, dynamic> json) {
    return SupportChatThread(
      threadId: (json['thread_id'] as String? ?? '').trim(),
      customerName: (json['customer_name'] as String? ?? 'Customer').trim(),
      customerPhone: (json['customer_phone'] as String? ?? '').trim(),
      customerLang: (json['customer_lang'] as String? ?? 'ru').trim(),
      lastMessage: (json['last_message'] as String? ?? '').trim(),
      lastSender: (json['last_sender'] as String? ?? '').trim(),
      lastCustomerMessage:
          (json['last_customer_message'] as String? ?? '').trim(),
      updatedAtMs: (json['updated_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      needsAdmin: json['needs_admin'] == true,
      answeredByApp: json['answered_by_app'] == true,
    );
  }

  factory SupportChatThread.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return SupportChatThread(
      threadId: (data['thread_id'] as String? ?? doc.id).trim(),
      customerName: (data['customer_name'] as String? ?? 'Customer').trim(),
      customerPhone: (data['customer_phone'] as String? ?? '').trim(),
      customerLang: (data['customer_lang'] as String? ?? 'ru').trim(),
      lastMessage: (data['last_message'] as String? ?? '').trim(),
      lastSender: (data['last_sender'] as String? ?? '').trim(),
      lastCustomerMessage:
          (data['last_customer_message'] as String? ?? '').trim(),
      updatedAtMs: (data['updated_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      needsAdmin: data['needs_admin'] == true,
      answeredByApp: data['answered_by_app'] == true,
    );
  }
}

class SupportInboxState {
  final List<SupportChatThread> threads;
  final Map<String, List<SupportChatMessage>> messagesByThread;

  const SupportInboxState({
    this.threads = const [],
    this.messagesByThread = const {},
  });

  SupportInboxState copyWith({
    List<SupportChatThread>? threads,
    Map<String, List<SupportChatMessage>>? messagesByThread,
  }) {
    return SupportInboxState(
      threads: threads ?? this.threads,
      messagesByThread: messagesByThread ?? this.messagesByThread,
    );
  }

  Map<String, dynamic> toJson() => {
        'threads': threads.map((e) => e.toJson()).toList(),
        'messages_by_thread': messagesByThread.map(
          (key, value) => MapEntry(
            key,
            value.map((message) => message.toJson()).toList(),
          ),
        ),
      };

  factory SupportInboxState.fromJson(Map<String, dynamic> json) {
    final rawThreads = json['threads'] as List<dynamic>? ?? const [];
    final rawMessages =
        (json['messages_by_thread'] as Map?)?.cast<String, dynamic>() ??
            const {};
    final messagesByThread = <String, List<SupportChatMessage>>{};
    for (final entry in rawMessages.entries) {
      final items = (entry.value as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => SupportChatMessage.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.text.isNotEmpty)
          .toList();
      messagesByThread[entry.key] = items;
    }
    return SupportInboxState(
      threads: rawThreads
          .whereType<Map>()
          .map((item) =>
              SupportChatThread.fromJson(Map<String, dynamic>.from(item)))
          .where((thread) => thread.threadId.isNotEmpty)
          .toList(),
      messagesByThread: messagesByThread,
    );
  }
}

SupportCenterConfig defaultSupportCenterConfig(String lang) {
  switch (lang) {
    case 'en':
      return const SupportCenterConfig(
        langCode: 'en',
        phoneNumber: '',
        callLabel: 'Call Support',
        chatLabel: 'Chat with us',
        chatSubtitle: '',
        chatIntro: '',
        faqs: [
          SupportFaqItem(
            id: 'default_delivery_time',
            question: 'How long does delivery usually take?',
            answer:
                'Delivery usually takes 35 to 60 minutes depending on traffic and order volume.',
          ),
          SupportFaqItem(
            id: 'default_cancel_order',
            question: 'Can I cancel my order?',
            answer:
                'Contact support as soon as possible. If the kitchen has not started preparation yet, we can usually help.',
          ),
          SupportFaqItem(
            id: 'default_payment_methods',
            question: 'What payment methods do you accept?',
            answer:
                'You can pay by cash, bank card, or available online payment methods in the app.',
          ),
        ],
      );
    case 'uz':
      return const SupportCenterConfig(
        langCode: 'uz',
        phoneNumber: '',
        callLabel: 'Qo‘llab-quvvatlashga qo‘ng‘iroq',
        chatLabel: 'Chat orqali yozing',
        chatSubtitle: '',
        chatIntro: '',
        faqs: [
          SupportFaqItem(
            id: 'default_delivery_time',
            question: 'Yetkazib berish odatda qancha vaqt oladi?',
            answer:
                'Yetkazib berish odatda tirbandlik va buyurtmalar soniga qarab 35 dan 60 daqiqagacha davom etadi.',
          ),
          SupportFaqItem(
            id: 'default_cancel_order',
            question: 'Buyurtmani bekor qilsam bo‘ladimi?',
            answer:
                'Iloji boricha tezroq qo‘llab-quvvatlash bilan bog‘laning. Oshxona tayyorlashni boshlamagan bo‘lsa, odatda yordam bera olamiz.',
          ),
          SupportFaqItem(
            id: 'default_payment_methods',
            question: 'Qaysi to‘lov usullari qabul qilinadi?',
            answer:
                'Naqd pul, bank kartasi yoki ilovadagi mavjud onlayn to‘lov usullari orqali to‘lashingiz mumkin.',
          ),
        ],
      );
    case 'ru':
    default:
      return const SupportCenterConfig(
        langCode: 'ru',
        phoneNumber: '',
        callLabel: 'Позвонить в поддержку',
        chatLabel: 'Написать в чат',
        chatSubtitle: '',
        chatIntro: '',
        faqs: [
          SupportFaqItem(
            id: 'default_delivery_time',
            question: 'Сколько обычно занимает доставка?',
            answer:
                'Обычно доставка занимает от 35 до 60 минут в зависимости от загруженности кухни и ситуации на дорогах.',
          ),
          SupportFaqItem(
            id: 'default_cancel_order',
            question: 'Можно ли отменить заказ?',
            answer:
                'Свяжитесь с поддержкой как можно быстрее. Если кухня еще не начала готовить, мы обычно можем помочь.',
          ),
          SupportFaqItem(
            id: 'default_payment_methods',
            question: 'Какие способы оплаты вы принимаете?',
            answer:
                'Вы можете оплатить наличными, банковской картой или доступными онлайн-способами оплаты в приложении.',
          ),
        ],
      );
  }
}

class SupportInboxNotifier extends StateNotifier<SupportInboxState> {
  final Ref _ref;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _threadsSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _messageSubs = {};

  SupportInboxNotifier(this._ref) : super(const SupportInboxState()) {
    loadFromCache();
    _startRemoteSync();
  }

  Future<void> loadFromCache() async {
    final raw = await AdminPanelCache().loadSupportInbox();
    if (raw == null) return;
    state = SupportInboxState.fromJson(raw);
    _ensureSubscriptions(state.threads.map((thread) => thread.threadId));
  }

  String threadIdForSession(UserSession session) {
    if (session.userId > 0) return 'user_${session.userId}';
    final digits = session.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) return 'phone_$digits';
    return 'guest';
  }

  Future<void> sendUserMessage({
    required UserSession session,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) return;
    final config = _ref.read(supportCenterProvider);
    final threadId = threadIdForSession(session);
    final now = DateTime.now();
    final customerName = session.fullName.trim().isEmpty
        ? (session.phone.trim().isEmpty ? 'Guest' : session.phone.trim())
        : session.fullName.trim();
    final customerPhone = session.phone.trim();
    final matched = _matchFaq(clean, config.faqs);
    final replyText = matched?.answer ??
        _supportEscalationText(session.preferredLang, config.phoneNumber);
    final replyTime = DateTime.now();
    final needsAdmin = matched == null;
    final currentThread = _threadById(threadId);
    final userMessage = SupportChatMessage(
      id: '${now.microsecondsSinceEpoch}_user',
      threadId: threadId,
      text: clean,
      sender: 'user',
      senderLabel: customerName,
      createdAtMs: now.millisecondsSinceEpoch,
    );
    final replyMessage = SupportChatMessage(
      id: '${replyTime.microsecondsSinceEpoch}_${needsAdmin ? 'bot_escalation' : 'bot'}',
      threadId: threadId,
      text: replyText,
      sender: needsAdmin ? 'bot_escalation' : 'bot',
      senderLabel: _assistantLabel(session.preferredLang),
      createdAtMs: replyTime.millisecondsSinceEpoch,
      faqId: matched?.id ?? '',
    );
    final nextThread = (currentThread ??
            SupportChatThread(
              threadId: threadId,
              customerName: customerName,
              customerPhone: customerPhone,
              customerLang: session.preferredLang,
              lastMessage: '',
              lastSender: '',
              lastCustomerMessage: '',
              updatedAtMs: now.millisecondsSinceEpoch,
              needsAdmin: false,
              answeredByApp: false,
            ))
        .copyWith(
      customerName: customerName,
      customerPhone: customerPhone,
      customerLang: session.preferredLang,
      lastMessage: replyText,
      lastSender: needsAdmin ? 'bot_escalation' : 'bot',
      lastCustomerMessage: clean,
      updatedAtMs: replyTime.millisecondsSinceEpoch,
      needsAdmin: needsAdmin,
      answeredByApp: !needsAdmin,
    );

    _upsertThread(nextThread);
    _upsertMessages(threadId, [userMessage, replyMessage]);
    await _persist();
    _ensureSubscriptions([threadId]);
    unawaited(_syncThreadToRemote(nextThread));
    unawaited(_syncMessagesToRemote(threadId, [userMessage, replyMessage]));
  }

  Future<void> sendCancellationRequest({
    required UserSession session,
    required int orderId,
    String? reason,
  }) async {
    if (orderId <= 0) return;
    final threadId = threadIdForSession(session);
    final now = DateTime.now();
    final customerName = session.fullName.trim().isEmpty
        ? (session.phone.trim().isEmpty ? 'Guest' : session.phone.trim())
        : session.fullName.trim();
    final customerPhone = session.phone.trim();
    final lang = session.preferredLang.trim().isEmpty
        ? _ref.read(localeProvider).languageCode
        : session.preferredLang.trim();
    final cleanReason = (reason ?? '').trim();
    final userText = _cancellationRequestUserText(
      orderId: orderId,
      lang: lang,
      reason: cleanReason.isEmpty ? null : cleanReason,
    );
    final replyTime = DateTime.now();
    final replyText = _cancellationRequestReplyText(
      orderId: orderId,
      lang: lang,
    );
    final currentThread = _threadById(threadId);
    final userMessage = SupportChatMessage(
      id: '${now.microsecondsSinceEpoch}_user_cancel_request',
      threadId: threadId,
      text: userText,
      sender: 'user',
      senderLabel: customerName,
      createdAtMs: now.millisecondsSinceEpoch,
    );
    final replyMessage = SupportChatMessage(
      id: '${replyTime.microsecondsSinceEpoch}_bot_escalation_cancel_request',
      threadId: threadId,
      text: replyText,
      sender: 'bot_escalation',
      senderLabel: _assistantLabel(lang),
      createdAtMs: replyTime.millisecondsSinceEpoch,
      faqId: 'cancel_request',
    );
    final nextThread = (currentThread ??
            SupportChatThread(
              threadId: threadId,
              customerName: customerName,
              customerPhone: customerPhone,
              customerLang: lang,
              lastMessage: '',
              lastSender: '',
              lastCustomerMessage: '',
              updatedAtMs: now.millisecondsSinceEpoch,
              needsAdmin: false,
              answeredByApp: false,
            ))
        .copyWith(
      customerName: customerName,
      customerPhone: customerPhone,
      customerLang: lang,
      lastMessage: replyText,
      lastSender: 'bot_escalation',
      lastCustomerMessage: userText,
      updatedAtMs: replyTime.millisecondsSinceEpoch,
      needsAdmin: true,
      answeredByApp: false,
    );

    _upsertThread(nextThread);
    _upsertMessages(threadId, [userMessage, replyMessage]);
    await _persist();
    _ensureSubscriptions([threadId]);
    unawaited(_syncThreadToRemote(nextThread));
    unawaited(_syncMessagesToRemote(threadId, [userMessage, replyMessage]));
  }

  Future<void> sendAdminReply({
    required String threadId,
    required String adminName,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    final currentThread = _threadById(threadId);
    final replyMessage = SupportChatMessage(
      id: '${now.microsecondsSinceEpoch}_admin',
      threadId: threadId,
      text: clean,
      sender: 'admin',
      senderLabel: adminName.trim().isEmpty ? 'Admin' : adminName.trim(),
      createdAtMs: now.millisecondsSinceEpoch,
    );
    final nextThread = (currentThread ??
            SupportChatThread(
              threadId: threadId,
              customerName: 'Customer',
              customerPhone: '',
              customerLang: _ref.read(localeProvider).languageCode,
              lastMessage: '',
              lastSender: '',
              lastCustomerMessage: '',
              updatedAtMs: now.millisecondsSinceEpoch,
              needsAdmin: false,
              answeredByApp: false,
            ))
        .copyWith(
      lastMessage: clean,
      lastSender: 'admin',
      updatedAtMs: now.millisecondsSinceEpoch,
      needsAdmin: false,
      answeredByApp: false,
    );

    _upsertThread(nextThread);
    _upsertMessages(threadId, [replyMessage]);
    await _persist();
    _ensureSubscriptions([threadId]);
    unawaited(_syncThreadToRemote(nextThread));
    unawaited(_syncMessagesToRemote(threadId, [replyMessage]));
  }

  SupportChatThread? _threadById(String threadId) {
    for (final thread in state.threads) {
      if (thread.threadId == threadId) return thread;
    }
    return null;
  }

  void _upsertThread(SupportChatThread thread) {
    final byId = {
      for (final item in state.threads) item.threadId: item,
      thread.threadId: thread,
    };
    state = state.copyWith(
      threads: byId.values.toList()
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
    );
  }

  void _upsertMessages(String threadId, List<SupportChatMessage> incoming) {
    final merged = _mergeMessages(
      state.messagesByThread[threadId] ?? const [],
      incoming,
    );
    state = state.copyWith(
      messagesByThread: {
        ...state.messagesByThread,
        threadId: merged,
      },
    );
  }

  List<SupportChatMessage> _mergeMessages(
    List<SupportChatMessage> current,
    List<SupportChatMessage> incoming,
  ) {
    final byId = {for (final item in current) item.id: item};
    for (final item in incoming) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    return merged;
  }

  SupportFaqItem? _matchFaq(String message, List<SupportFaqItem> faqs) {
    return _matchSupportFaq(message, faqs);
  }

  String _assistantLabel(String lang) {
    switch (lang) {
      case 'en':
        return 'Sushi XL Assistant';
      case 'uz':
        return 'Sushi XL Yordamchisi';
      case 'ru':
      default:
        return 'Ассистент Sushi XL';
    }
  }

  String _cancellationRequestUserText({
    required int orderId,
    required String lang,
    String? reason,
  }) {
    switch (lang) {
      case 'uz':
        return reason == null || reason.isEmpty
            ? 'Buyurtma #$orderId ni bekor qilishni so‘rayman.'
            : 'Buyurtma #$orderId ni bekor qilishni so‘rayman.\nSabab: $reason';
      case 'en':
        return reason == null || reason.isEmpty
            ? 'Please cancel my order #$orderId.'
            : 'Please cancel my order #$orderId.\nReason: $reason';
      case 'ru':
      default:
        return reason == null || reason.isEmpty
            ? 'Пожалуйста, отмените мой заказ #$orderId.'
            : 'Пожалуйста, отмените мой заказ #$orderId.\nПричина: $reason';
    }
  }

  String _cancellationRequestReplyText({
    required int orderId,
    required String lang,
  }) {
    switch (lang) {
      case 'uz':
        return 'Buyurtma #$orderId bo‘yicha bekor qilish so‘rovi support guruhiga yuborildi. Bekor qilish hali mumkin yoki yo‘qligini tez orada tasdiqlaymiz.';
      case 'en':
        return 'Your cancellation request for order #$orderId has been sent to support. We will confirm shortly whether cancellation is still possible.';
      case 'ru':
      default:
        return 'Ваш запрос на отмену заказа #$orderId отправлен в поддержку. Мы скоро подтвердим, возможно ли ещё отменить заказ.';
    }
  }

  Future<void> _persist() async {
    await AdminPanelCache().saveSupportInbox(state.toJson());
  }

  void _startRemoteSync() {
    if (Firebase.apps.isEmpty) {
      debugPrint(
          '[support] firebase unavailable, remote support inbox sync disabled');
      return;
    }
    try {
      _threadsSub = FirebaseFirestore.instance
          .collection('support_threads')
          .orderBy('updated_at_ms', descending: true)
          .limit(50)
          .snapshots()
          .listen(
        (snapshot) async {
          final merged = {
            for (final thread in state.threads) thread.threadId: thread,
          };
          for (final doc in snapshot.docs) {
            final remoteThread = SupportChatThread.fromDocument(doc);
            merged[remoteThread.threadId] = remoteThread;
          }
          state = state.copyWith(
            threads: merged.values.toList()
              ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs)),
          );
          _ensureSubscriptions(merged.keys);
          await _persist();
        },
        onError: (Object e) {
          debugPrint('[support] thread sync failed: $e');
        },
      );
    } catch (e) {
      debugPrint('[support] remote inbox unavailable: $e');
    }
  }

  void _ensureSubscriptions(Iterable<String> threadIds) {
    if (Firebase.apps.isEmpty) return;
    for (final threadId in threadIds) {
      if (threadId.trim().isEmpty || _messageSubs.containsKey(threadId)) {
        continue;
      }
      _messageSubs[threadId] = FirebaseFirestore.instance
          .collection('support_threads')
          .doc(threadId)
          .collection('messages')
          .orderBy('created_at_ms')
          .snapshots()
          .listen(
        (snapshot) async {
          final remoteMessages = snapshot.docs
              .map((doc) => SupportChatMessage.fromDocument(threadId, doc))
              .toList();
          final merged = _mergeMessages(
            state.messagesByThread[threadId] ?? const [],
            remoteMessages,
          );
          state = state.copyWith(
            messagesByThread: {
              ...state.messagesByThread,
              threadId: merged,
            },
          );
          await _persist();
        },
        onError: (Object e) {
          debugPrint('[support] message sync failed ($threadId): $e');
        },
      );
    }
  }

  Future<void> _syncThreadToRemote(SupportChatThread thread) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('support_threads')
          .doc(thread.threadId)
          .set(thread.toRemoteJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint(
          '[support] remote thread write failed (${thread.threadId}): $e');
    }
  }

  Future<void> _syncMessagesToRemote(
    String threadId,
    List<SupportChatMessage> messages,
  ) async {
    if (Firebase.apps.isEmpty) return;
    for (final message in messages) {
      try {
        await FirebaseFirestore.instance
            .collection('support_threads')
            .doc(threadId)
            .collection('messages')
            .doc(message.id)
            .set(message.toRemoteJson(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('[support] remote message write failed (${message.id}): $e');
      }
    }
  }

  @override
  void dispose() {
    _threadsSub?.cancel();
    for (final sub in _messageSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}

class SupportCenterNotifier extends StateNotifier<SupportCenterConfig> {
  final Ref _ref;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _configSub;
  String _lastSyncedLang = '';
  int _lastSyncedAtMs = 0;

  SupportCenterNotifier(this._ref)
      : super(defaultSupportCenterConfig(
          _ref.read(localeProvider).languageCode,
        )) {
    loadFromCache();
    unawaited(loadFromBackend(force: true));
    _startRemoteSync();
  }

  Future<void> loadFromCache() async {
    final raw = await AdminPanelCache().loadSupportConfig();
    if (raw == null) return;
    state = SupportCenterConfig.fromJson(
      raw,
      fallbackLang: _ref.read(localeProvider).languageCode,
    );
  }

  Future<void> ensureBackendSynced({
    bool force = false,
    String? lang,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final currentLang = (lang ?? _ref.read(localeProvider).languageCode).trim();
    if (!force &&
        currentLang == _lastSyncedLang &&
        (now - _lastSyncedAtMs) < 25000) {
      return;
    }
    await loadFromBackend(force: force, lang: currentLang);
  }

  Future<void> loadFromBackend({
    bool force = false,
    String? lang,
  }) async {
    final currentLang = (lang ?? _ref.read(localeProvider).languageCode).trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        currentLang == _lastSyncedLang &&
        (now - _lastSyncedAtMs) < 25000) {
      return;
    }
    try {
      final repo = _ref.read(publicRepositoryProvider);
      final settings = await repo.getSettings(lang: currentLang);
      final faqs = await repo.getFaqs(lang: currentLang);
      if (settings == null) return;
      final defaults = defaultSupportCenterConfig(currentLang);
      final nextFaqs = faqs
          .where((item) => item.question.isNotEmpty && item.answer.isNotEmpty)
          .map(
            (item) => SupportFaqItem(
              id: item.id,
              question: item.question,
              answer: item.answer,
            ),
          )
          .toList();
      state = SupportCenterConfig(
        langCode: currentLang,
        phoneNumber: settings.supportPhone.isEmpty
            ? state.phoneNumber
            : settings.supportPhone,
        callLabel: settings.callLabel.isEmpty
            ? defaults.callLabel
            : settings.callLabel,
        chatLabel: settings.chatLabel.isEmpty
            ? defaults.chatLabel
            : settings.chatLabel,
        chatSubtitle: settings.chatSubtitle.isEmpty
            ? defaults.chatSubtitle
            : settings.chatSubtitle,
        chatIntro: settings.chatIntro.isEmpty
            ? defaults.chatIntro
            : settings.chatIntro,
        faqs: nextFaqs.isEmpty ? defaults.faqs : nextFaqs,
      );
      _lastSyncedLang = currentLang;
      _lastSyncedAtMs = DateTime.now().millisecondsSinceEpoch;
      await _persist();
    } catch (e) {
      debugPrint('[support] backend support config load failed: $e');
    }
  }

  Future<void> updatePhoneNumber(String phoneNumber) async {
    final clean = phoneNumber.trim();
    if (clean.isEmpty) return;
    state = state.copyWith(phoneNumber: clean);
    await _persist();
  }

  Future<void> addFaq({
    required String question,
    required String answer,
  }) async {
    final cleanQuestion = question.trim();
    final cleanAnswer = answer.trim();
    if (cleanQuestion.isEmpty || cleanAnswer.isEmpty) return;
    final next = [
      ...state.faqs,
      SupportFaqItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        question: cleanQuestion,
        answer: cleanAnswer,
      ),
    ];
    state = state.copyWith(faqs: next);
    await _persist();
  }

  Future<void> updateFaq(SupportFaqItem item) async {
    final next = [
      for (final faq in state.faqs) faq.id == item.id ? item : faq,
    ];
    state = state.copyWith(faqs: next);
    await _persist();
  }

  Future<void> deleteFaq(String id) async {
    state = state.copyWith(
      faqs: state.faqs.where((e) => e.id != id).toList(),
    );
    await _persist();
  }

  String threadIdForSession(UserSession session) {
    if (session.userId > 0) return 'user_${session.userId}';
    final digits = session.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) return 'phone_$digits';
    return 'guest';
  }

  Future<void> sendUserMessage({
    required UserSession session,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty || Firebase.apps.isEmpty) return;
    final threadId = threadIdForSession(session);
    final threadRef =
        FirebaseFirestore.instance.collection('support_threads').doc(threadId);
    final now = DateTime.now();
    final customerName = session.fullName.trim().isEmpty
        ? (session.phone.trim().isEmpty ? 'Guest' : session.phone.trim())
        : session.fullName.trim();
    final customerPhone = session.phone.trim();

    await threadRef.set({
      'thread_id': threadId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_lang': session.preferredLang,
      'last_message': clean,
      'last_sender': 'user',
      'last_customer_message': clean,
      'updated_at_ms': now.millisecondsSinceEpoch,
      'updated_at': FieldValue.serverTimestamp(),
      'needs_admin': false,
    }, SetOptions(merge: true));

    await threadRef
        .collection('messages')
        .doc('${now.microsecondsSinceEpoch}_user')
        .set({
      'text': clean,
      'sender': 'user',
      'sender_label': customerName,
      'created_at_ms': now.millisecondsSinceEpoch,
      'created_at': FieldValue.serverTimestamp(),
    });

    final matched = _matchFaq(clean);
    final replyText = matched?.answer ??
        _supportEscalationText(session.preferredLang, state.phoneNumber);
    final replyTime = DateTime.now();
    final needsAdmin = matched == null;

    await threadRef
        .collection('messages')
        .doc(
            '${replyTime.microsecondsSinceEpoch}_${needsAdmin ? 'bot_escalation' : 'bot'}')
        .set({
      'text': replyText,
      'sender': needsAdmin ? 'bot_escalation' : 'bot',
      'sender_label': 'Sushi XL Assistant',
      'created_at_ms': replyTime.millisecondsSinceEpoch,
      'created_at': FieldValue.serverTimestamp(),
      'faq_id': matched?.id,
    });

    await threadRef.set({
      'last_message': replyText,
      'last_sender': needsAdmin ? 'bot_escalation' : 'bot',
      'updated_at_ms': replyTime.millisecondsSinceEpoch,
      'updated_at': FieldValue.serverTimestamp(),
      'needs_admin': needsAdmin,
      'answered_by_app': !needsAdmin,
    }, SetOptions(merge: true));
  }

  Future<void> sendAdminReply({
    required String threadId,
    required String adminName,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty || Firebase.apps.isEmpty) return;
    final now = DateTime.now();
    final threadRef =
        FirebaseFirestore.instance.collection('support_threads').doc(threadId);
    await threadRef
        .collection('messages')
        .doc('${now.microsecondsSinceEpoch}_admin')
        .set({
      'text': clean,
      'sender': 'admin',
      'sender_label': adminName.trim().isEmpty ? 'Admin' : adminName.trim(),
      'created_at_ms': now.millisecondsSinceEpoch,
      'created_at': FieldValue.serverTimestamp(),
    });
    await threadRef.set({
      'last_message': clean,
      'last_sender': 'admin',
      'updated_at_ms': now.millisecondsSinceEpoch,
      'updated_at': FieldValue.serverTimestamp(),
      'needs_admin': false,
      'answered_by_app': false,
    }, SetOptions(merge: true));
  }

  SupportFaqItem? _matchFaq(String message) {
    return _matchSupportFaq(message, state.faqs);
  }

  Future<void> _persist() async {
    final json = state.toJson();
    await AdminPanelCache().saveSupportConfig(json);
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('support_center')
          .doc('config')
          .set(json, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[support] config sync failed: $e');
    }
  }

  void _startRemoteSync() {
    if (Firebase.apps.isEmpty) {
      debugPrint(
          '[support] firebase unavailable, remote support sync disabled');
      return;
    }
    try {
      _configSub = FirebaseFirestore.instance
          .collection('support_center')
          .doc('config')
          .snapshots()
          .listen((snapshot) async {
        final data = snapshot.data();
        if (data == null || data.isEmpty) return;
        state = SupportCenterConfig.fromJson(
          data,
          fallbackLang: _ref.read(localeProvider).languageCode,
        );
        await AdminPanelCache().saveSupportConfig(state.toJson());
      });
    } catch (e) {
      debugPrint('[support] remote config unavailable: $e');
    }
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }
}

String _supportEscalationText(String lang, String phoneNumber) {
  switch (lang) {
    case 'en':
      return 'I could not answer that clearly. Our admin will review this chat. If it is urgent, call $phoneNumber.';
    case 'uz':
      return 'Bu savolga aniq javob bera olmadim. Admin ushbu chatni ko‘rib chiqadi. Shoshilinch bo‘lsa, $phoneNumber raqamiga qo‘ng‘iroq qiling.';
    case 'ru':
    default:
      return 'Я не смог ответить на это достаточно точно. Администратор просмотрит этот чат. Если вопрос срочный, позвоните по номеру $phoneNumber.';
  }
}

SupportFaqItem? _matchSupportFaq(String message, List<SupportFaqItem> faqs) {
  final messageTokens = _tokenizeSupportText(message);
  if (messageTokens.isEmpty) return null;
  SupportFaqItem? best;
  var bestScore = 0;
  final lowerMessage = message.toLowerCase();
  for (final faq in faqs) {
    final faqTokens = _tokenizeSupportText('${faq.question} ${faq.answer}');
    var score = _faqIntentBoost(lowerMessage, faq.question.toLowerCase());
    for (final token in messageTokens) {
      if (faqTokens.contains(token)) score += 1;
    }
    if (faq.question.toLowerCase().contains(lowerMessage)) {
      score += 3;
    }
    if (score > bestScore) {
      bestScore = score;
      best = faq;
    }
  }
  if (bestScore >= 2) return best;
  if (messageTokens.length <= 2 && bestScore >= 1) return best;
  return null;
}

Set<String> _tokenizeSupportText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zA-Zа-яА-Я0-9қўғҳёіїʼ’\\s]+'), ' ')
      .split(RegExp(r'\s+'))
      .map((e) => e.trim())
      .where((e) => e.length >= 3)
      .toSet();
}

int _faqIntentBoost(String messageLower, String questionLower) {
  int boost = 0;
  final deliveryHints = ['delivery', 'deliver', 'достав', 'yetkaz', 'курьер'];
  final cancelHints = ['cancel', 'отмен', 'bekor'];
  final paymentHints = [
    'payment',
    'pay',
    'оплат',
    'card',
    'cash',
    'карта',
    'налич',
    'to‘lov',
    "to'lov",
    'tolov',
  ];
  if (_containsAny(messageLower, deliveryHints) &&
      _containsAny(questionLower, deliveryHints)) {
    boost += 3;
  }
  if (_containsAny(messageLower, cancelHints) &&
      _containsAny(questionLower, cancelHints)) {
    boost += 3;
  }
  if (_containsAny(messageLower, paymentHints) &&
      _containsAny(questionLower, paymentHints)) {
    boost += 3;
  }
  return boost;
}

bool _containsAny(String value, List<String> variants) {
  for (final variant in variants) {
    if (value.contains(variant)) return true;
  }
  return false;
}

final supportCenterProvider =
    StateNotifierProvider<SupportCenterNotifier, SupportCenterConfig>(
  (ref) => SupportCenterNotifier(ref),
);

final supportInboxProvider =
    StateNotifierProvider<SupportInboxNotifier, SupportInboxState>(
  (ref) => SupportInboxNotifier(ref),
);

final supportThreadListProvider = Provider<List<SupportChatThread>>((ref) {
  final threads = ref.watch(supportInboxProvider).threads;
  return [...threads]..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
});

final supportThreadMessagesProvider =
    Provider.family<List<SupportChatMessage>, String>((ref, threadId) {
  final messages =
      ref.watch(supportInboxProvider).messagesByThread[threadId] ?? const [];
  return [...messages]..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
});
