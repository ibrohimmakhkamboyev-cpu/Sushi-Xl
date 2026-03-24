String? normalizeRemoteImageUrl(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  return text.replaceAll(
    RegExp(
      r'(?:_original){2,}(?=\.[A-Za-z0-9]+(?:[?#].*)?$)',
      caseSensitive: false,
    ),
    '_original',
  );
}
