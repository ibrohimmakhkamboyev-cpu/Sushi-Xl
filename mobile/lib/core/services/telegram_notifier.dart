import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class TelegramSendResult {
  final bool ok;
  final String? error;

  const TelegramSendResult._(this.ok, this.error);

  const TelegramSendResult.success() : this._(true, null);
  const TelegramSendResult.failed(String message) : this._(false, message);
}

class TelegramNotifier {
  final Dio _dio;
  final String _botToken;
  final String _chatId;

  TelegramNotifier({
    required Dio dio,
    required String botToken,
    required String chatId,
  })  : _dio = dio,
        _botToken = botToken.trim(),
        _chatId = chatId.trim();

  bool get isConfigured => _botToken.isNotEmpty && _chatId.isNotEmpty;

  String? _normalizeChatId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'-?\d+').firstMatch(trimmed);
    if (match == null) return null;
    return match.group(0);
  }

  Future<TelegramSendResult> _sendText({
    required String chatId,
    required String text,
  }) async {
    final res = await _dio.post(
      'https://api.telegram.org/bot$_botToken/sendMessage',
      data: {
        'chat_id': chatId,
        'text': text,
      },
    );
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return const TelegramSendResult.success();
    }
    if (data is Map && data['description'] is String) {
      return TelegramSendResult.failed(data['description'] as String);
    }
    return const TelegramSendResult.failed('Unknown Telegram API response.');
  }

  Future<TelegramSendResult> sendOrderNotification({
    required int orderId,
    required int userId,
    required String customerName,
    required String phone,
    required DateTime createdAt,
    required String deliveryType,
    required String paymentMethod,
    required String orderStatus,
    required String paymentStatus,
    required int? addressId,
    required String? address,
    required double? consumerLat,
    required double? consumerLng,
    required String? notes,
    required double total,
    required List<String> itemLines,
  }) async {
    if (!isConfigured) {
      return const TelegramSendResult.failed(
        'Telegram not configured: TELEGRAM_BOT_TOKEN or TELEGRAM_GROUP_ID is empty.',
      );
    }
    final normalizedChatId = _normalizeChatId(_chatId);
    if (normalizedChatId == null) {
      return TelegramSendResult.failed(
        'Invalid TELEGRAM_GROUP_ID format: "$_chatId"',
      );
    }

    final safeAddress =
        (address == null || address.trim().isEmpty) ? '-' : address.trim();
    final safeNotes =
        (notes == null || notes.trim().isEmpty) ? '-' : notes.trim();
    final safeName = customerName.trim().isEmpty ? '-' : customerName.trim();
    final safePhone = phone.trim().isEmpty ? '-' : phone.trim();
    final safeItems = itemLines.isEmpty ? const ['-'] : itemLines;
    String coords = '-';
    String googleMapsLink = '-';
    String yandexMapsLink = '-';
    if (consumerLat != null && consumerLng != null) {
      final lat = consumerLat.toStringAsFixed(6);
      final lng = consumerLng.toStringAsFixed(6);
      coords = '$lat, $lng';
      googleMapsLink = 'https://maps.google.com/?q=$lat,$lng';
      yandexMapsLink = 'https://yandex.com/maps/?pt=$lng,$lat&z=17';
    }

    final message = StringBuffer()
      ..writeln('New order #$orderId')
      ..writeln('Created: ${createdAt.toIso8601String()}')
      ..writeln('User ID: $userId')
      ..writeln('Customer: $safeName')
      ..writeln('Phone: $safePhone')
      ..writeln('Delivery: $deliveryType')
      ..writeln('Order status: $orderStatus')
      ..writeln('Payment status: $paymentStatus')
      ..writeln('Address ID: ${addressId ?? '-'}')
      ..writeln('Address: $safeAddress')
      ..writeln('Customer location: $coords')
      ..writeln('Google Maps: $googleMapsLink')
      ..writeln('Yandex Maps: $yandexMapsLink')
      ..writeln('Payment: $paymentMethod')
      ..writeln('Total: ${total.toStringAsFixed(0)} UZS')
      ..writeln('Items:')
      ..writeln(safeItems.map((line) => '- $line').join('\n'))
      ..writeln('Notes: $safeNotes');

    try {
      final text = message.toString();
      var result = await _sendText(chatId: normalizedChatId, text: text);

      // Common issue: supergroup id requires -100 prefix.
      if (!result.ok &&
          result.error != null &&
          result.error!.toLowerCase().contains('chat not found') &&
          normalizedChatId.startsWith('-') &&
          !normalizedChatId.startsWith('-100')) {
        final altChatId = '-100${normalizedChatId.substring(1)}';
        result = await _sendText(chatId: altChatId, text: text);
      }
      return result;
    } catch (e, st) {
      debugPrint('Telegram notification failed: $e');
      debugPrintStack(stackTrace: st);
      if (e is DioException) {
        final payload = e.response?.data;
        if (payload is Map && payload['description'] is String) {
          return TelegramSendResult.failed(payload['description'] as String);
        }
        return TelegramSendResult.failed(e.message ?? 'Network error');
      }
      return TelegramSendResult.failed(e.toString());
    }
  }
}
