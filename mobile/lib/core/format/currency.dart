String formatUzs(num? value) {
  if (value == null) return '';
  final rounded = value.round();
  final raw = rounded.toString();
  final buf = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final idx = raw.length - i;
    buf.write(raw[i]);
    if (idx > 1 && idx % 3 == 1) {
      buf.write(' ');
    }
  }
  return '${buf.toString()} UZS';
}
