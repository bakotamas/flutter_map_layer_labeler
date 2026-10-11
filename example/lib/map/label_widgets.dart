import 'package:flutter/material.dart';

import '../data/gis_data.dart';

// Widget labels need their size before they are laid out, so their texts are
// measured with the same (not inherited) styles they are drawn with.

const _cityChipStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: Color(0xFF263238),
  decoration: TextDecoration.none,
);

const _riverTagStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  fontSize: 10,
  fontWeight: FontWeight.w600,
  color: Color(0xFFFFFFFF),
  decoration: TextDecoration.none,
);

const _countryNameStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Color(0xFF4A3F4E),
  decoration: TextDecoration.none,
);

const _countryInfoStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  fontSize: 10,
  color: Color(0xFF6D6470),
  decoration: TextDecoration.none,
);

double _textWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width.ceilToDouble();
}

/// 1 679 000 -> "1.7M".
String compactNumber(int value) => switch (value) {
  >= 1000000000 => '${(value / 1000000000).toStringAsFixed(1)}B',
  >= 1000000 => '${(value / 1000000).toStringAsFixed(1)}M',
  >= 1000 => '${(value / 1000).round()}k',
  _ => '$value',
};

/// 1679000 -> "1 679 000".
String groupedNumber(int value) {
  final digits = '$value';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The marker of a city: a dot, or a star if it is a capital.
class CityMarker extends StatelessWidget {
  const new({
    required this.city,
    required this.size,
    required this.onTap,
    super.key,
  });

  final City city;

  /// The size of the marker.
  final double size;
  final ValueChanged<City> onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onTap(city),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: city.isCapital
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF455A64),
            border: Border.all(
              color: city.isCapital
                  ? const Color(0xFF37474F)
                  : const Color(0xFFFFFFFF),
              width: 1.5,
            ),
          ),
          child: city.isCapital
              ? Icon(Icons.star, size: size - 4, color: const Color(0xFFC62828))
              : null,
        ),
      ),
    );
  }
}

/// The widget label of a city: a chip with its name and population.
class CityChip extends StatelessWidget {
  const new({required this.city, required this.onTap, super.key});

  final City city;
  final ValueChanged<City> onTap;

  static String _text(City city) =>
      '${city.name} · ${compactNumber(city.population)}';

  static Size sizeOf(City city) =>
      Size(_textWidth(_text(city), _cityChipStyle) + 18, 22);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      elevation: 1.5,
      shape: StadiumBorder(
        side: BorderSide(
          color: city.isCapital
              ? const Color(0xFFC62828)
              : const Color(0xFFB0BEC5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(city),
        child: Center(
          child: Text(
            _text(city),
            style: _cityChipStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}

/// The widget label of a river: a small tag with its name.
class RiverTag extends StatelessWidget {
  const new({required this.river, super.key});

  final River river;

  static Size sizeOf(River river) =>
      Size(_textWidth(river.name, _riverTagStyle) + 12, 16);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1976D2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFFFFFF)),
      ),
      child: Center(
        child: Text(
          river.name,
          style: _riverTagStyle,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

/// The widget label of a country: a card with its name and population.
class CountryCard extends StatelessWidget {
  const new({required this.country, super.key});

  final Country country;

  static String _info(Country country) =>
      '${compactNumber(country.population)} people';

  static Size sizeOf(Country country) {
    final name = _textWidth(country.name, _countryNameStyle);
    final info = _textWidth(_info(country), _countryInfoStyle);
    return Size((name > info ? name : info) + 16, 36);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBCAFC0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            country.name,
            style: _countryNameStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
          Text(
            _info(country),
            style: _countryInfoStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }
}
