String canonicalOrderStatus(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return 'pending';
  if (value == 'telegram_only') return 'telegram_only';
  if (value.contains('cancel')) return 'cancelled';
  if (value.contains('deliver') ||
      value.contains('complete') ||
      value.contains('done') ||
      value.contains('closed')) {
    return 'delivered';
  }
  if (value == 'on_the_way' ||
      value.contains('on the way') ||
      value.contains('courier') ||
      value.contains('driver') ||
      value.contains('rider') ||
      value.contains('dispatch') ||
      value.contains('sent')) {
    return 'on_the_way';
  }
  if (value.contains('prepar') || value.contains('cook')) {
    return 'preparing';
  }
  if (value.contains('accept')) return 'accepted';
  if (value.contains('pending') ||
      value.contains('new') ||
      value.contains('wait')) {
    return 'pending';
  }
  return value;
}

bool isTerminalOrderStatus(String raw) {
  final normalized = canonicalOrderStatus(raw);
  return normalized == 'cancelled' || normalized == 'delivered';
}

int activeOrderTimelineStep(String raw) {
  switch (canonicalOrderStatus(raw)) {
    case 'delivered':
      return 3;
    case 'on_the_way':
      return 2;
    case 'preparing':
      return 1;
    case 'accepted':
    case 'pending':
    case 'telegram_only':
    case 'cancelled':
    default:
      return 0;
  }
}

String orderStatusLabelKey(String raw) {
  switch (canonicalOrderStatus(raw)) {
    case 'cancelled':
      return 'status_cancelled';
    case 'delivered':
      return 'status_delivered';
    case 'on_the_way':
      return 'status_on_the_way';
    case 'preparing':
      return 'status_preparing';
    case 'accepted':
      return 'status_accepted';
    case 'telegram_only':
      return 'status_telegram_only';
    case 'pending':
    default:
      return 'status_pending';
  }
}
