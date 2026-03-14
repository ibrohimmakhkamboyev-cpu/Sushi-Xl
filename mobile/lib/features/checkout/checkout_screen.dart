import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/state/providers.dart';
import '../../data/models/order_models.dart';
import '../../data/models/address_models.dart';
import '../../core/localization/sushi_localizations.dart';
import '../../core/format/currency.dart';
import '../../core/cache/location_cache.dart';
import '../../core/cache/session_cache.dart';
import '../../core/config.dart';
import '../../core/maps/yandex_map_view.dart';
import '../../core/maps/yandex_map_types.dart';
import '../../core/maps/geocoder_proxy_client.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _targetAccuracyMeters = 50.0;
  static const _pageBackground = Color(0xFFF8F6F6);

  final _proxyGeocoder = GeocoderProxyClient();
  final _searchSuggestions = <ProxyPlace>[];
  bool _loading = false;
  String _deliveryType = 'delivery';
  String _paymentMethod = 'cash';
  final _notesController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  int? _addressId;
  double _pickedLat = restaurantLat;
  double _pickedLng = restaurantLng;
  bool _hasConsumerCoords = false;
  bool _prefilledFromSavedLocation = false;
  bool _prefilledFromAddressBook = false;
  bool _pendingStoredAddressReverse = false;
  bool _resolvingAddress = false;
  bool _searchingAddress = false;
  bool _locating = false;
  bool _permissionDeniedForever = false;
  double _mapZoom = 15;
  String _placeName = '';
  String _formattedAddress = '';
  Timer? _searchDebounce;

  bool get _canSubmit {
    return !_loading;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _proxyGeocoder.dispose();
    _notesController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    var session = ref.read(userSessionProvider) ??
        UserSession.guest(preferredLang: ref.read(localeProvider).languageCode);
    final t = SushiLocalizations.of(context);
    if (_deliveryType == 'delivery' && _addressId == null) {
      final ok = await _ensureAddressSavedForSubmit();
      if (!ok) return;
    }
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;
    final menu = await ref.read(menuProvider.future);
    final validProductIds = menu.categories
        .expand((category) => category.products)
        .map((product) => product.id)
        .toSet();
    final invalidItems = cart.items
        .where((item) => !validProductIds.contains(item.product.id))
        .toList(growable: false);
    if (invalidItems.isNotEmpty) {
      for (final item in invalidItems) {
        ref.read(cartProvider.notifier).removeItem(
              item.product,
              modifiers: item.modifiers,
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cart was updated. Please review items and place order again.',
            ),
          ),
        );
      }
      return;
    }
    final activeCart = ref.read(cartProvider);
    if (activeCart.items.isEmpty) return;
    final total =
        activeCart.items.fold<double>(0, (sum, item) => sum + item.total());
    final itemLines = activeCart.items.map((item) {
      final basePrice = item.unitPrice.toStringAsFixed(0);
      final modifierText = item.modifiers.map((selected) {
        final mod =
            item.product.modifiers.where((m) => m.id == selected.modifierId);
        final modName =
            mod.isEmpty ? 'mod#${selected.modifierId}' : mod.first.name;
        return '$modName (+${selected.price.toStringAsFixed(0)})';
      }).join(', ');
      final modsPart = modifierText.isEmpty ? '' : ' | mods: $modifierText';
      return '${item.title} x${item.qty} | base: $basePrice UZS$modsPart | line total: ${item.total().toStringAsFixed(0)} UZS';
    }).toList();

    setState(() => _loading = true);
    try {
      if (!useBackend) {
        throw Exception(
            'Backend ordering is disabled. Enable backend + Poster.');
      }
      session = await _ensureOrderUserSession(session, t);
      final items = activeCart.items
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
                      modifierId: m.modifierId, price: m.price))
                  .toList(),
            ),
          )
          .toList();
      final orderNotes = _buildOrderNotes();
      final req = CreateOrderRequest(
        userId: session.userId,
        items: items,
        deliveryType: activeCart.deliveryType,
        addressId: _deliveryType == 'delivery' ? _addressId : null,
        scheduledAt: null,
        notes: orderNotes,
        paymentMethod: activeCart.paymentMethod,
      );
      int orderId;
      String orderStatus;
      String paymentStatus;
      final order = await ref.read(orderRepositoryProvider).createOrder(req);
      if ((order.posterOrderId ?? '').trim().isEmpty) {
        throw Exception(
          'Order was not synced to Poster. Check backend Poster configuration.',
        );
      }
      orderId = order.id;
      orderStatus = order.status;
      paymentStatus = order.paymentStatus;
      final telegramResult =
          await ref.read(telegramNotifierProvider).sendOrderNotification(
                orderId: orderId,
                userId: session.userId,
                customerName: session.fullName,
                phone: _phoneController.text.trim().isEmpty
                    ? session.phone
                    : _phoneController.text,
                createdAt: DateTime.now(),
                deliveryType: _deliveryType,
                paymentMethod: _paymentMethod,
                orderStatus: orderStatus,
                paymentStatus: paymentStatus,
                addressId: _addressId,
                address: _deliveryType == 'delivery'
                    ? _addressController.text
                    : null,
                consumerLat: _deliveryType == 'delivery' && _hasConsumerCoords
                    ? _pickedLat
                    : null,
                consumerLng: _deliveryType == 'delivery' && _hasConsumerCoords
                    ? _pickedLng
                    : null,
                notes: _notesController.text,
                total: total,
                itemLines: itemLines,
              );
      if (!telegramResult.ok) {
        debugPrint(
          'Telegram notify failed after order creation: ${telegramResult.error}',
        );
      }
      await ref.read(localOrderHistoryProvider.notifier).addOrderFromCart(
            orderId: orderId,
            status: orderStatus,
            paymentStatus: paymentStatus,
            createdAt: DateTime.now(),
            cartItems: activeCart.items,
          );
      await ref.read(cartProvider.notifier).clear();
      if (mounted) context.go('/order-success?orderId=$orderId');
    } catch (e) {
      final errorMessage = _orderErrorMessage(e);
      await _sendTelegramOrderFailureAlert(
        session: session,
        errorMessage: errorMessage,
        total: total,
        itemLines: itemLines,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('order_failed'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _orderErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        final backendError = data['error'];
        if (backendError is String && backendError.trim().isNotEmpty) {
          return backendError.trim();
        }
      }
      final message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return error.toString();
  }

  Future<void> _sendTelegramOrderFailureAlert({
    required UserSession session,
    required String errorMessage,
    required double total,
    required List<String> itemLines,
  }) async {
    final telegramResult = await ref
        .read(telegramNotifierProvider)
        .sendOrderNotification(
          orderId: 0,
          userId: session.userId,
          customerName: session.fullName.trim().isEmpty
              ? 'Guest'
              : session.fullName.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? session.phone
              : _phoneController.text,
          createdAt: DateTime.now(),
          deliveryType: _deliveryType,
          paymentMethod: _paymentMethod,
          orderStatus: 'poster_sync_failed',
          paymentStatus: 'unpaid',
          addressId: _addressId,
          address: _deliveryType == 'delivery' ? _addressController.text : null,
          consumerLat: _deliveryType == 'delivery' && _hasConsumerCoords
              ? _pickedLat
              : null,
          consumerLng: _deliveryType == 'delivery' && _hasConsumerCoords
              ? _pickedLng
              : null,
          notes:
              '[ORDER FAILED BEFORE SAVE] $errorMessage | ${_notesController.text}',
          total: total,
          itemLines: itemLines,
        );
    if (!telegramResult.ok) {
      debugPrint('Telegram failure-alert send failed: ${telegramResult.error}');
    }
  }

  Future<UserSession> _ensureOrderUserSession(
    UserSession session,
    SushiLocalizations t,
  ) async {
    if (session.userId > 0 && session.accessToken.trim().isNotEmpty) {
      return session;
    }
    final inputPhone = _phoneController.text.trim();
    final phone = inputPhone.isNotEmpty ? inputPhone : session.phone.trim();
    if (phone.isEmpty) {
      throw Exception('${t.t('phone')} is required.');
    }
    final fullName =
        session.fullName.trim().isNotEmpty ? session.fullName.trim() : 'Guest';
    final localeCode = ref.read(localeProvider).languageCode;
    final auth = ref.read(authRepositoryProvider);
    final challenge = await auth.requestLoginCode(
      phone: phone,
      fullName: fullName,
      preferredLang: localeCode,
    );
    String code = challenge.debugCode.trim();
    if (code.isEmpty) {
      code = await _promptCheckoutOtpCode(t, phone) ?? '';
      code = code.trim();
    }
    if (code.isEmpty) {
      throw Exception(t.t('otp_code_required'));
    }
    final login = await auth.verifyLoginCode(
      phone: phone,
      code: code,
      fullName: fullName,
      preferredLang: localeCode,
    );
    final upgraded = UserSession(
      userId: login.userId,
      phone: login.phone,
      fullName: login.fullName,
      preferredLang: login.preferredLang,
      gender: session.gender,
      accessToken: login.accessToken,
    );
    ref.read(userSessionProvider.notifier).state = upgraded;
    await SessionCache().save(upgraded.toJson());
    return upgraded;
  }

  Future<String?> _promptCheckoutOtpCode(
    SushiLocalizations t,
    String phone,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.t('login_required')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.t('otp_code_prompt')}\n$phone'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: t.t('otp_code_label'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.t('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(t.t('continue')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _saveAddress() async {
    final session = ref.read(userSessionProvider);
    if (session == null) return;
    final t = SushiLocalizations.of(context);
    final addressLine = await _effectiveAddressLine(t);
    if (addressLine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('address_required'))),
      );
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _addressController.text = addressLine;
    }
    if (!useBackend || session.userId <= 0) {
      _addressId = _addressId ?? -1;
      await _syncSharedLocation(addressLine);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.t('address_saved'))),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final created = await ref.read(addressRepositoryProvider).createAddress(
            AddressIn(
              userId: session.userId,
              label: t.t('address'),
              addressLine: addressLine,
              lat: _hasConsumerCoords ? _pickedLat : null,
              lng: _hasConsumerCoords ? _pickedLng : null,
            ),
          );
      _addressId = created.id;
      await _syncSharedLocation(addressLine);
      ref.invalidate(addressesProvider(session.userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.t('address_saved'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Address save failed: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.t('address_save_failed'))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensureAddressSavedForSubmit() async {
    final session = ref.read(userSessionProvider);
    if (session == null) return false;
    final t = SushiLocalizations.of(context);
    if (_addressId != null) return true;
    final addressLine = await _effectiveAddressLine(t);
    if (addressLine == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.t('please_enter_address'))));
      }
      return false;
    }
    if (_addressController.text.trim().isEmpty) {
      _addressController.text = addressLine;
    }
    if (!useBackend || session.userId <= 0) {
      _addressId = _addressId ?? -1;
      await _syncSharedLocation(addressLine);
      return true;
    }
    try {
      final created = await ref.read(addressRepositoryProvider).createAddress(
            AddressIn(
              userId: session.userId,
              label: t.t('address'),
              addressLine: addressLine,
              lat: _hasConsumerCoords ? _pickedLat : null,
              lng: _hasConsumerCoords ? _pickedLng : null,
            ),
          );
      _addressId = created.id;
      await _syncSharedLocation(addressLine);
      ref.invalidate(addressesProvider(session.userId));
      return true;
    } catch (e) {
      debugPrint('Address service unavailable, using manual fallback: $e');
      if (!mounted) return false;
      // Fallback mode: allow checkout with manual address in order notes.
      await _syncSharedLocation(addressLine);
      return true;
    }
  }

  Future<String?> _effectiveAddressLine(SushiLocalizations t) async {
    final typed = _addressController.text.trim();
    final resolvedFull = _formattedAddress.trim();
    if (resolvedFull.isNotEmpty) return resolvedFull;
    if (typed.isNotEmpty) return typed;
    if (!_hasConsumerCoords) return null;

    await _resolveAddressFromMap(_pickedLat, _pickedLng);
    final resolved = _formattedAddress.trim().isNotEmpty
        ? _formattedAddress.trim()
        : _addressController.text.trim();
    if (resolved.isNotEmpty) return resolved;
    return null;
  }

  Future<void> _resolveAddressFromMap(
    double lat,
    double lng, {
    bool clearSavedAddressId = true,
  }) async {
    if (_resolvingAddress) return;
    setState(() => _resolvingAddress = true);
    try {
      final place = await _proxyGeocoder.reverse(
        lat: lat,
        lon: lng,
        lang: _proxyLang(),
      );
      if (place == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No places found. Try another search.')),
          );
        }
        return;
      }
      await _applyPlaceSelection(
        place,
        clearSuggestions: true,
        clearSavedAddressId: clearSavedAddressId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No places found. Try another search.')),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  Future<void> _searchAddressFromText() async {
    final query = _addressController.text.trim();
    return _runAddressSearch(
      query,
      autoSelectTop: true,
      showNoResultsMessage: true,
    );
  }

  Future<void> _runAddressSearch(
    String query, {
    required bool autoSelectTop,
    required bool showNoResultsMessage,
  }) async {
    if (query.isEmpty) {
      if (mounted && showNoResultsMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No places found. Try another search.')),
        );
      }
      return;
    }
    setState(() => _searchingAddress = true);
    try {
      final results = await _proxyGeocoder.geocode(
        text: query,
        lang: _proxyLang(),
      );
      if (results.isNotEmpty) {
        if (mounted) {
          final top = results.take(5).toList();
          final latestQuery = _addressController.text.trim();
          if (latestQuery != query.trim()) return;
          setState(() {
            _searchSuggestions
              ..clear()
              ..addAll(top);
          });
          if (autoSelectTop) {
            await _applyPlaceSelection(top.first, clearSuggestions: false);
          }
        }
      } else {
        if (mounted) {
          setState(() => _searchSuggestions.clear());
          if (showNoResultsMessage) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No places found. Try another search.')),
            );
          }
        }
      }
    } catch (_) {
      if (mounted && showNoResultsMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No places found. Try another search.')),
        );
      }
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  void _handleAddressInputChanged(String value) {
    final trimmed = value.trim();
    _searchDebounce?.cancel();

    if (!mounted) return;
    setState(() {
      _addressId = null;
      _searchSuggestions.clear();
      final matchesSelected = trimmed.isNotEmpty &&
          trimmed.toLowerCase() ==
              _composeAddress(_placeName, _formattedAddress)
                  .trim()
                  .toLowerCase();
      if (!matchesSelected) {
        _placeName = '';
        _formattedAddress = '';
      }
      if (trimmed.isEmpty) {
        _hasConsumerCoords = false;
        _pickedLat = restaurantLat;
        _pickedLng = restaurantLng;
        _mapZoom = 15;
      }
    });

    if (trimmed.length < 3) return;
    _searchDebounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final latest = _addressController.text.trim();
      if (latest.length < 3) return;
      unawaited(
        _runAddressSearch(
          latest,
          autoSelectTop: false,
          showNoResultsMessage: false,
        ),
      );
    });
  }

  Future<void> _useCurrentLocation() async {
    final t = SushiLocalizations.of(context);
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.t('location_service_disabled'))),
          );
        }
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Permission.locationWhenInUse.status;
      if (permission.isDenied) {
        permission = await Permission.locationWhenInUse.request();
      }
      if (permission.isPermanentlyDenied || permission.isRestricted) {
        setState(() => _permissionDeniedForever = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }
      if (!permission.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }

      var pos = await _safeCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No places found. Try another search.')),
          );
        }
        return;
      }
      if (pos.accuracy > _targetAccuracyMeters) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Уточняю местоположение…')),
          );
        }
        pos = await _refineCurrentPosition(pos);
        if (pos == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No places found. Try another search.')),
            );
          }
          return;
        }
      }
      if (!_validLatLon(pos.latitude, pos.longitude)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid GPS coordinates received.')),
          );
        }
        return;
      }
      final resolvedPos = pos;
      setState(() {
        _permissionDeniedForever = false;
        _pickedLat = resolvedPos.latitude;
        _pickedLng = resolvedPos.longitude;
        _hasConsumerCoords = true;
        _addressId = null;
        _searchSuggestions.clear();
        if (_mapZoom < 16) _mapZoom = 16;
      });
      await _resolveAddressFromMap(_pickedLat, _pickedLng);
    } catch (e) {
      debugPrint('Current location flow failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<Position?> _safeCurrentPosition() async {
    Position? bestCandidate;
    final attempts = <(LocationAccuracy, Duration)>[
      (LocationAccuracy.bestForNavigation, const Duration(seconds: 10)),
      (LocationAccuracy.high, const Duration(seconds: 8)),
      (LocationAccuracy.medium, const Duration(seconds: 6)),
    ];
    for (final attempt in attempts) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: attempt.$1,
          timeLimit: attempt.$2,
        );
        if (!_validLatLon(pos.latitude, pos.longitude)) continue;
        if (pos.accuracy <= _targetAccuracyMeters) return pos;
        if (bestCandidate == null || pos.accuracy < bestCandidate.accuracy) {
          bestCandidate = pos;
        }
      } catch (_) {
        // Try next accuracy tier.
      }
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final isRecent =
            DateTime.now().difference(last.timestamp).inMinutes <= 5;
        if (isRecent &&
            last.accuracy <= _targetAccuracyMeters &&
            _validLatLon(last.latitude, last.longitude)) {
          return last;
        }
        if (_validLatLon(last.latitude, last.longitude) &&
            (bestCandidate == null || last.accuracy < bestCandidate.accuracy)) {
          bestCandidate = last;
        }
      }
    } catch (_) {
      // Continue with live stream attempt.
    }
    try {
      final live = await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 8));
      if (!_validLatLon(live.latitude, live.longitude)) return bestCandidate;
      if (live.accuracy <= _targetAccuracyMeters) return live;
      if (bestCandidate == null || live.accuracy < bestCandidate.accuracy) {
        bestCandidate = live;
      }
    } catch (_) {
      // Fallback to best observed candidate below.
    }
    return bestCandidate;
  }

  Future<Position?> _refineCurrentPosition(Position current) async {
    var best = current;
    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );
      if (_validLatLon(fresh.latitude, fresh.longitude) &&
          fresh.accuracy < best.accuracy) {
        best = fresh;
      }
      if (best.accuracy <= _targetAccuracyMeters) return best;
    } catch (_) {
      // Try the live stream below.
    }
    try {
      final live = await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 8));
      if (_validLatLon(live.latitude, live.longitude) &&
          live.accuracy < best.accuracy) {
        best = live;
      }
    } catch (_) {
      // Keep the best fix seen so far.
    }
    return best;
  }

  bool _validLatLon(double lat, double lon) {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  bool _looksLikeCoordinateAddress(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    return RegExp(
      r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$',
    ).hasMatch(text);
  }

  bool _isAdministrativeLabel(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return true;
    return text == 'узбекистан' ||
        text == 'uzbekistan' ||
        text == 'ташкент' ||
        text == 'tashkent' ||
        text.contains('махалл') ||
        text.contains('махалля') ||
        text.contains('махаллин') ||
        text.contains('сход граждан') ||
        text.contains('mahall') ||
        text.contains('мфй');
  }

  String _visibleAddressLabel(String placeName, String formattedAddress) {
    final short = placeName.trim();
    final long = formattedAddress.trim();
    if (short.isNotEmpty && !_isAdministrativeLabel(short)) return short;
    final parts = long
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final part in parts.reversed) {
      if (!_isAdministrativeLabel(part)) return part;
    }
    return short.isNotEmpty ? short : long;
  }

  String _applyStoredAddressText({
    required String address,
    double? lat,
    double? lon,
  }) {
    final raw = address.trim();
    if (!_looksLikeCoordinateAddress(raw)) {
      _formattedAddress = raw;
      _placeName = _visibleAddressLabel('', raw);
      _addressController.text = _placeName;
      return raw;
    }

    _addressController.clear();
    _formattedAddress = '';
    _placeName = '';
    if (lat == null || lon == null || !_validLatLon(lat, lon)) {
      return '';
    }
    if (_pendingStoredAddressReverse) return '';

    _pendingStoredAddressReverse = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pendingStoredAddressReverse = false;
        return;
      }
      unawaited(
        _resolveAddressFromMap(
          lat,
          lon,
          clearSavedAddressId: false,
        ).whenComplete(() {
          _pendingStoredAddressReverse = false;
        }),
      );
    });
    return '';
  }

  Future<void> _syncSharedLocation(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;
    final current = ref.read(deliveryLocationProvider);
    final lat = _hasConsumerCoords ? _pickedLat : (current?.lat ?? _pickedLat);
    final lng = _hasConsumerCoords ? _pickedLng : (current?.lng ?? _pickedLng);
    final loc = DeliveryLocation(address: trimmed, lat: lat, lng: lng);
    ref.read(deliveryLocationProvider.notifier).state = loc;
    final scope = _locationScope();
    if (scope == null) return;
    await LocationCache().save(
      address: trimmed,
      lat: lat,
      lng: lng,
      scope: scope,
    );
  }

  String? _locationScope() {
    final session = ref.read(userSessionProvider);
    if (session == null) return null;
    if (session.userId > 0) return 'uid_${session.userId}';
    final phone = session.phone.trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    return null;
  }

  String _proxyLang() {
    return 'ru_RU';
  }

  String _composeAddress(String placeName, String formattedAddress) {
    return _visibleAddressLabel(placeName, formattedAddress);
  }

  Future<void> _applyPlaceSelection(
    ProxyPlace place, {
    required bool clearSuggestions,
    bool clearSavedAddressId = true,
  }) async {
    setState(() {
      _pickedLat = place.lat;
      _pickedLng = place.lon;
      _hasConsumerCoords = true;
      _permissionDeniedForever = false;
      if (clearSavedAddressId) {
        _addressId = null;
      }
      if (_mapZoom < 16) _mapZoom = 16;
      if (clearSuggestions) _searchSuggestions.clear();
    });
    _placeName = _visibleAddressLabel(
      place.placeName.trim(),
      place.formattedAddress.trim(),
    );
    _formattedAddress = place.formattedAddress.trim();
    final combined = _composeAddress(_placeName, _formattedAddress);
    _addressController.text = combined;
    await _syncSharedLocation(combined);
  }

  Future<void> _selectSuggestion(ProxyPlace place) async {
    await _applyPlaceSelection(place, clearSuggestions: true);
  }

  Widget _addressSearchField(SushiLocalizations t, {bool embedded = false}) {
    final field = embedded
        ? Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2DADA)),
            ),
            child: TextField(
              controller: _addressController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchAddressFromText(),
              onChanged: _handleAddressInputChanged,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: t.t('add_address'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                suffixIcon: (_resolvingAddress || _searchingAddress)
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _searchAddressFromText,
                      ),
              ),
            ),
          )
        : _InputCard(
            child: TextField(
              controller: _addressController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchAddressFromText(),
              onChanged: _handleAddressInputChanged,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: t.t('add_address'),
                suffixIcon: (_resolvingAddress || _searchingAddress)
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _searchAddressFromText,
                      ),
              ),
            ),
          );
    return Column(
      children: [
        field,
        if (_searchSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SearchSuggestionsCard(
            items: _searchSuggestions,
            onSelect: _selectSuggestion,
          ),
        ],
      ],
    );
  }

  Widget _buildDeliveryMapSection(SushiLocalizations t) {
    final selectedLabel = _placeName.trim().isNotEmpty
        ? _placeName.trim()
        : (_formattedAddress.trim().isNotEmpty
            ? _formattedAddress.trim()
            : t.t('location_not_set'));
    return Container(
      decoration: BoxDecoration(
        color: _pageBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2DADA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 232,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: YandexMapView(
                      lat: _pickedLat,
                      lng: _pickedLng,
                      zoom: _mapZoom,
                      selectable: true,
                      markers: [
                        YandexMapMarker(
                          _pickedLat,
                          _pickedLng,
                          title: selectedLabel,
                          subtitle: _formattedAddress.trim(),
                        ),
                      ],
                      addressLabel: _addressController.text.trim(),
                      onTap: (lat, lng) {
                        setState(() {
                          _pickedLat = lat;
                          _pickedLng = lng;
                          _hasConsumerCoords = true;
                          _addressId = null;
                          _searchSuggestions.clear();
                          if (_mapZoom < 16) _mapZoom = 16;
                        });
                        _resolveAddressFromMap(lat, lng);
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      _MapIconButton(
                        onTap: _locating ? null : _useCurrentLocation,
                        child: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF231816),
                                ),
                              )
                            : const Icon(
                                Icons.my_location_rounded,
                                size: 18,
                                color: Color(0xFF231816),
                              ),
                      ),
                      const SizedBox(height: 8),
                      _MapZoomControls(
                        onZoomIn: _zoomInMap,
                        onZoomOut: _zoomOutMap,
                        backgroundColor: _pageBackground,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.place_rounded,
                    color: Color(0xFFEE482B),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF231816),
                        ),
                      ),
                      if (_formattedAddress.trim().isNotEmpty &&
                          _formattedAddress.trim() != selectedLabel) ...[
                        const SizedBox(height: 3),
                        Text(
                          _formattedAddress.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFF6C6265),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_permissionDeniedForever)
                  _MapIconButton(
                    onTap: openAppSettings,
                    child: const Icon(
                      Icons.settings_rounded,
                      size: 18,
                      color: Color(0xFF231816),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressPickerCard(SushiLocalizations t) {
    return Container(
      decoration: BoxDecoration(
        color: _pageBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2DADA)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _addressSearchField(t, embedded: true),
          const SizedBox(height: 12),
          _buildDeliveryMapSection(t),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _loading ? null : _saveAddress,
              child: Text(t.t('save_address')),
            ),
          ),
        ],
      ),
    );
  }

  void _zoomInMap() {
    setState(() {
      _mapZoom = (_mapZoom + 1).clamp(10.0, 19.0).toDouble();
    });
  }

  void _zoomOutMap() {
    setState(() {
      _mapZoom = (_mapZoom - 1).clamp(10.0, 19.0).toDouble();
    });
  }

  String? _buildOrderNotes() {
    final segments = <String>[];
    final userNote = _notesController.text.trim();
    if (userNote.isNotEmpty) {
      segments.add(userNote);
    }
    if (_deliveryType == 'delivery' && _addressId == null) {
      final manualAddress = _addressController.text.trim();
      if (manualAddress.isNotEmpty) {
        segments.add('Delivery address: $manualAddress');
      }
    }
    if (segments.isEmpty) return null;
    return segments.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final session = ref.watch(userSessionProvider);
    final localLocation = ref.watch(deliveryLocationProvider);
    final addressesAsync =
        (!useBackend || session == null || session.userId <= 0)
            ? null
            : ref.watch(addressesProvider(session.userId));
    if (!_prefilledFromSavedLocation && localLocation != null) {
      _pickedLat = localLocation.lat;
      _pickedLng = localLocation.lng;
      _hasConsumerCoords = true;
      _addressId = null;
      _prefilledFromSavedLocation = true;
      _applyStoredAddressText(
        address: localLocation.address,
        lat: localLocation.lat,
        lon: localLocation.lng,
      );
    }
    if (_phoneController.text.isEmpty) {
      final phone = session?.phone;
      if (phone != null) {
        _phoneController.text = phone;
      }
    }
    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: t.t('checkout')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  _SectionTitle(title: t.t('delivery_details')),
                  const SizedBox(height: 8),
                  if (_deliveryType == 'delivery') ...[
                    _InputLabel(label: t.t('address')),
                    if (addressesAsync != null)
                      addressesAsync.when(
                        data: (items) {
                          if (_addressController.text.trim().isEmpty &&
                              _addressId == null &&
                              localLocation == null &&
                              items.isNotEmpty) {
                            _addressId = items.first.id;
                          }
                          final selected = _addressId == null
                              ? null
                              : items.where((e) => e.id == _addressId).isEmpty
                                  ? null
                                  : items.firstWhere((e) => e.id == _addressId);
                          if (selected != null &&
                              !_prefilledFromAddressBook &&
                              _addressController.text.trim().isEmpty) {
                            if (selected.lat != null && selected.lng != null) {
                              _pickedLat = selected.lat!;
                              _pickedLng = selected.lng!;
                              _hasConsumerCoords = true;
                            } else {
                              _hasConsumerCoords = false;
                            }
                            _prefilledFromAddressBook = true;
                            _applyStoredAddressText(
                              address: selected.addressLine,
                              lat: selected.lat,
                              lon: selected.lng,
                            );
                          }
                          if (localLocation != null || items.isEmpty) {
                            return _buildAddressPickerCard(t);
                          }
                          return Column(
                            children: [
                              _InputCard(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _addressId,
                                    isExpanded: true,
                                    hint: Text(t.t('address')),
                                    items: items
                                        .map(
                                          (a) => DropdownMenuItem(
                                            value: a.id,
                                            child:
                                                Text(a.label ?? a.addressLine),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v == null) return;
                                      final next = items.firstWhere(
                                        (e) => e.id == v,
                                        orElse: () => items.first,
                                      );
                                      setState(() {
                                        _addressId = v;
                                        _prefilledFromAddressBook = true;
                                        if (next.lat != null &&
                                            next.lng != null) {
                                          _pickedLat = next.lat!;
                                          _pickedLng = next.lng!;
                                          _hasConsumerCoords = true;
                                        } else {
                                          _hasConsumerCoords = false;
                                        }
                                      });
                                      final applied = _applyStoredAddressText(
                                        address: next.addressLine,
                                        lat: next.lat,
                                        lon: next.lng,
                                      );
                                      if (applied.isNotEmpty) {
                                        _syncSharedLocation(applied);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildAddressPickerCard(t),
                            ],
                          );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (err, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.t('address_service_offline_manual'),
                              style: const TextStyle(
                                  color: Color(0xFFB45309), fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            _buildAddressPickerCard(t),
                          ],
                        ),
                      ),
                    if (addressesAsync == null) _buildAddressPickerCard(t),
                    const SizedBox(height: 16),
                  ],
                  _InputLabel(label: t.t('phone')),
                  _InputCard(
                    child: TextField(
                      controller: _phoneController,
                      readOnly: true,
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(title: t.t('payment_method')),
                  const SizedBox(height: 8),
                  _PaymentOption(
                    title: t.t('payment_cash'),
                    subtitle: t.t('payment_subtitle_cash'),
                    icon: Icons.payments,
                    selected: _paymentMethod == 'cash',
                    onTap: () => setState(() => _paymentMethod = 'cash'),
                  ),
                  _PaymentOption(
                    title: t.t('payment_card'),
                    subtitle: t.t('payment_subtitle_card'),
                    icon: Icons.credit_card,
                    selected: _paymentMethod == 'card',
                    onTap: () => setState(() => _paymentMethod = 'card'),
                  ),
                  _PaymentOption(
                    title: t.t('payment_online'),
                    subtitle: t.t('payment_subtitle_coming_soon'),
                    icon: Icons.account_balance_wallet,
                    selected: _paymentMethod == 'online',
                    onTap: () => setState(() => _paymentMethod = 'online'),
                    disabled: true,
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(title: t.t('order_notes')),
                  const SizedBox(height: 8),
                  _InputCard(
                    child: TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                          border: InputBorder.none, hintText: t.t('add_note')),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _OrderSummary(total: ref.read(cartProvider.notifier).total()),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        loading: _loading,
        total: ref.read(cartProvider.notifier).total(),
        enabled: _canSubmit,
        onSubmit: _submit,
      ),
    );
  }
}

class _SearchSuggestionsCard extends StatelessWidget {
  final List<ProxyPlace> items;
  final void Function(ProxyPlace place) onSelect;

  const _SearchSuggestionsCard({
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Column(
        children: items
            .map(
              (place) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text(
                  place.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  place.formattedAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelect(place),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final Color backgroundColor;
  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      decoration: BoxDecoration(
        color: backgroundColor.withOpacity(0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D0D0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onZoomIn,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: const SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  '+',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE7E7E7)),
          InkWell(
            onTap: onZoomOut,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(10)),
            child: const SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  '-',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _MapIconButton({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F6F6).withOpacity(0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFD8D0D0)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new)),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _InputCard extends StatelessWidget {
  final Widget child;
  const _InputCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: child,
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _PaymentOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFEE482B) : const Color(0xFFBDBDBD);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF2F2F2) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  selected ? const Color(0xFFEE482B) : const Color(0xFFE5E5E5),
              width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFEE482B).withOpacity(0.15)
                    : const Color(0xFFF3F3F3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: selected
                      ? const Color(0xFFEE482B)
                      : const Color(0xFF9A9A9A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9A9A9A))),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Color(0xFFEE482B), shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final double total;
  const _OrderSummary({required this.total});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.t('order_summary'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _Row(label: t.t('subtotal'), value: formatUzs(total)),
          _Row(label: t.t('delivery_fee'), value: '15 000 UZS'),
          const Divider(),
          _Row(
              label: t.t('total'),
              value: formatUzs(total + 15000),
              strong: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _Row({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9A9A9A))),
          Text(value,
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool loading;
  final double total;
  final VoidCallback onSubmit;
  final bool enabled;
  const _BottomBar(
      {required this.loading,
      required this.total,
      required this.onSubmit,
      required this.enabled});

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Color(0x11000000), blurRadius: 8, offset: Offset(0, -2))
      ]),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEE482B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: (!enabled || loading) ? null : onSubmit,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(loading ? '...' : t.t('place_order'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              const Text('|', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              Text(formatUzs(total + 15000),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
