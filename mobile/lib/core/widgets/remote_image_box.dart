import 'package:flutter/material.dart';

import '../format/image_url.dart';

class RemoteImageBox extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Color backgroundColor;

  const RemoteImageBox({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.backgroundColor = const Color(0x1F000000),
  });

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = normalizeRemoteImageUrl(imageUrl);
    final radius = borderRadius ?? BorderRadius.zero;
    final content = ColoredBox(
      color: backgroundColor,
      child: normalizedUrl == null
          ? _ImageFallback(backgroundColor: backgroundColor)
          : Image.network(
              normalizedUrl,
              fit: fit,
              errorBuilder: (_, __, ___) =>
                  _ImageFallback(backgroundColor: backgroundColor),
            ),
    );
    return ClipRRect(
      borderRadius: radius,
      child: width == null && height == null
          ? SizedBox.expand(child: content)
          : SizedBox(width: width, height: height, child: content),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final Color backgroundColor;

  const _ImageFallback({required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: Color(0xFF9A9A9A),
          size: 28,
        ),
      ),
    );
  }
}
