/// Extracts WGS84 coordinates from common Google Maps URL patterns.
class GoogleMapsCoordsParser {
  GoogleMapsCoordsParser._();

  static final RegExp _atQuery = RegExp(
    r'[@/](-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  static final RegExp _qParam = RegExp(
    r'[?&]q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// Returns (lat, lng) if a single pair is found; prefers @lat,lng in path.
  static ({double lat, double lng})? tryParsePair(String input) {
    final String s = input.trim();
    if (s.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(s);
    if (uri != null) {
      final String combined = '${uri.path}?${uri.query}';
      final ({double lat, double lng})? fromPath = _firstPair(_atQuery, combined);
      if (fromPath != null) {
        return fromPath;
      }
      final ({double lat, double lng})? fromQ = _firstPair(_qParam, '?${uri.query}');
      if (fromQ != null) {
        return fromQ;
      }
    }
    return _firstPair(_atQuery, s) ?? _firstPair(_qParam, s);
  }

  static ({double lat, double lng})? _firstPair(RegExp re, String haystack) {
    final Match? m = re.firstMatch(haystack);
    if (m == null) {
      return null;
    }
    final double? la = double.tryParse(m.group(1)!);
    final double? ln = double.tryParse(m.group(2)!);
    if (la == null || ln == null) {
      return null;
    }
    if (la.abs() > 90 || ln.abs() > 180) {
      return null;
    }
    return (lat: la, lng: ln);
  }
}
