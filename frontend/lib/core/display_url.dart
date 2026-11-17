/// Website values of leads, for display and for opening.
///
/// Scraped websites are often long tracking links
/// (`https://www.example-dental.com/?utm_source=gmb&utm_medium=organic`) or
/// Google redirects (`https://www.google.com/url?q=https://example.com/...`).
/// Cards show a short, readable name ([displayWebsite]); tapping opens the
/// ORIGINAL value ([websiteLaunchUri]); copy and exports keep the raw value
/// untouched. Everything here is pure and safe to call with any input.
library;

/// Values the scraper writes when a field is empty.
const Set<String> _placeholders = {'', 'n/a', 'na', 'null', 'none', 'nil', '-', '—', 'undefined', 'no website'};

/// Hosts where the first path segment(s) name the business
/// (`facebook.com/joesplumbing`).
const Set<String> _profileHosts = {
  'facebook.com',
  'fb.com',
  'instagram.com',
  'twitter.com',
  'x.com',
  'linkedin.com',
  'tiktok.com',
  'youtube.com',
  'yelp.com',
  'linktr.ee',
  'pinterest.com',
  'threads.net',
  'wa.me',
  't.me',
};

/// Single path segments that carry no meaning for a reader.
final RegExp _noisePath = RegExp(
  r'^(index|default|home|main)(\.(html?|php|aspx?|jsp))?$|^[a-z]{2}([-_][a-z]{2})?$',
  caseSensitive: false,
);
final RegExp _indexPage = RegExp(r'^(index|default|home)(\.(html?|php|aspx?|jsp))?$', caseSensitive: false);

final RegExp _schemeWithSlashes = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):\/\/');
final RegExp _anyScheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):(?!\d)');
final RegExp _controlChars = RegExp(r'[\u0000-\u001F\u007F]');
final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
final RegExp _hostLabel = RegExp(r'^[\p{L}\p{M}\p{N}_](?:[\p{L}\p{M}\p{N}_-]*[\p{L}\p{M}\p{N}_])?$', unicode: true);
final RegExp _googleHost = RegExp(r'^(www\.)?google\.[a-z]{2,3}(\.[a-z]{2})?$');

/// The http(s) [Uri] to open for a lead's website, or `null` when [raw] is
/// empty, a placeholder ("N/A"), not a plausible web address, or uses any
/// other scheme (`javascript:`, `data:`, `file:`, `mailto:`, ...).
///
/// The value is NOT rewritten: tracking parameters and redirects are kept
/// exactly as scraped. Only a missing scheme is completed with `https://`
/// (`example.com` -> `https://example.com`, `//example.com` ->
/// `https://example.com`). Tabs and newlines are removed first, as browsers
/// do, so `java\tscript:` cannot slip through.
Uri? websiteLaunchUri(String? raw) {
  final s = _clean(raw);
  if (s == null) return null;
  final withScheme = _withScheme(s);
  if (withScheme == null) return null;
  final uri = Uri.tryParse(withScheme);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (_displayHost(uri) == null) return null;
  return uri;
}

/// True when [raw] can be opened as a website ([websiteLaunchUri] is not
/// null).
bool isOpenableWebsite(String? raw) => websiteLaunchUri(raw) != null;

/// Short, readable name of a website for cards and tables:
///
/// * scheme, `www.`, user info, query, fragment and trailing `/` are dropped
///   (so `utm_*`, `gclid`, `fbclid`, ... never show);
/// * Google (`google.*/url?q=`) and Facebook/Instagram (`l.facebook.com/l.php?u=`)
///   redirects are unwrapped to their target;
/// * the host is lower-cased; Unicode hosts stay Unicode and punycode
///   (`xn--...`) stays punycode (never converted, so look-alike domains are
///   not disguised);
/// * only the site name is shown (`example-dental.com`), except on social
///   and directory sites where the path names the business
///   (`facebook.com/joesplumbing`); pass [keepPath] to also keep a short
///   path on other sites (`example.com/doha`);
/// * a non-default port is kept (`192.168.1.10:8080`).
///
/// Returns `''` when there is nothing openable ([websiteLaunchUri] is null).
/// [maxPathLength] limits the kept path (without the leading `/`).
String displayWebsite(String? raw, {int maxPathLength = 28, bool keepPath = false}) {
  var uri = websiteLaunchUri(raw);
  if (uri == null) return '';
  for (var i = 0; i < 3; i++) {
    final target = _redirectTarget(uri!);
    if (target == null) break;
    uri = target;
  }
  final target = uri!;
  final host = _displayHost(target);
  if (host == null) return '';
  final profile = _profileHosts.contains(_stripMobile(host));
  final shownHost = profile ? _stripMobile(host) : host;
  final port = target.hasPort ? ':${target.port}' : '';
  final path = (profile || keepPath) ? _displayPath(target, profile: profile, maxLength: maxPathLength) : '';
  return path.isEmpty ? '$shownHost$port' : '$shownHost$port/$path';
}

// ------------------------------------------------------------------ helpers

String? _clean(String? raw) {
  if (raw == null) return null;
  final s = raw.replaceAll(_controlChars, '').trim();
  if (_placeholders.contains(s.toLowerCase())) return null;
  if (s.contains(RegExp(r'\s'))) {
    // A URL with a space inside the host is garbage; spaces in a path are
    // tolerated only after the host (encoded by Uri).
    final hostPart = s.replaceFirst(_schemeWithSlashes, '').split(RegExp(r'[/?#]')).first;
    if (hostPart.contains(RegExp(r'\s'))) return null;
  }
  return s;
}

/// [s] with an `http(s)://` scheme, or null when it has another scheme.
String? _withScheme(String s) {
  final m = _schemeWithSlashes.firstMatch(s);
  if (m != null) {
    final scheme = m.group(1)!.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? s : null;
  }
  if (s.startsWith('//')) return 'https:$s';
  // `javascript:alert(1)`, `data:text/html,...`, `mailto:a@b.c`, ... but not
  // `example.com:8080/path` (a digit after the colon is a port).
  if (_anyScheme.hasMatch(s)) return null;
  return 'https://$s';
}

/// Lower-case, percent-decoded host of [uri] without `www.`, or null when
/// it is not a plausible public or IP host.
String? _displayHost(Uri uri) {
  var host = uri.host;
  if (host.isEmpty) return null;
  if (host.contains(':')) return '[$host]'; // IPv6 literal
  try {
    host = Uri.decodeComponent(host);
  } catch (_) {
    return null;
  }
  host = host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  final ip = _ipv4.firstMatch(host);
  if (ip != null) {
    final ok = [1, 2, 3, 4].every((g) => int.parse(ip.group(g)!) <= 255);
    return ok ? host : null;
  }
  if (host == 'localhost') return host;
  final labels = host.split('.');
  if (labels.length < 2) return null;
  if (!labels.every(_hostLabel.hasMatch)) return null;
  final tld = labels.last;
  if (tld.length < 2 || RegExp(r'^\d+$').hasMatch(tld)) return null;
  final noWww = host.replaceFirst(RegExp(r'^www\d*\.'), '');
  return noWww.contains('.') ? noWww : host;
}

String _stripMobile(String host) => host.replaceFirst(RegExp(r'^(m|mobile|web|business)\.'), '');

/// The target of a known redirect link, when it is itself http(s).
Uri? _redirectTarget(Uri uri) {
  final host = uri.host.toLowerCase();
  String? param;
  if (_googleHost.hasMatch(host) && (uri.path == '/url' || uri.path == '/local_url')) {
    param = uri.queryParameters['q'] ?? uri.queryParameters['url'];
  } else if ((host == 'l.facebook.com' || host == 'lm.facebook.com' || host == 'l.instagram.com') &&
      uri.path == '/l.php') {
    param = uri.queryParameters['u'];
  }
  if (param == null || param.trim().isEmpty) return null;
  final target = Uri.tryParse(param.trim());
  if (target == null || (target.scheme != 'http' && target.scheme != 'https')) return null;
  if (_displayHost(target) == null) return null;
  return target;
}

String _displayPath(Uri uri, {required bool profile, required int maxLength}) {
  final segments = <String>[];
  for (final raw in uri.pathSegments) {
    if (raw.isEmpty) continue;
    var seg = raw;
    try {
      seg = Uri.decodeComponent(raw);
    } catch (_) {}
    segments.add(seg.trim());
  }
  segments.removeWhere((s) => s.isEmpty);
  if (segments.isEmpty) return '';

  if (profile) {
    // facebook.com/joesplumbing, linkedin.com/company/acme
    final first = segments.first.toLowerCase();
    if (first == 'profile.php' || first == 'sharer' || first == 'sharer.php' || first == 'l.php') return '';
    final keep = (first == 'company' || first == 'pages' || first == 'in' || first == 'biz' || first == 'channel' || first == 'c')
        ? segments.take(2).toList()
        : segments.take(1).toList();
    final path = keep.join('/');
    return path.length <= maxLength ? path : '';
  }

  // example.com/index.html, example.com/en/, example.com/en/home
  while (segments.isNotEmpty && _indexPage.hasMatch(segments.last)) {
    segments.removeLast();
  }
  if (segments.length == 1 && _noisePath.hasMatch(segments.first)) return '';
  if (segments.isEmpty || segments.length > 2) return '';
  final path = segments.join('/');
  if (path.length > maxLength) return '';
  return path;
}
