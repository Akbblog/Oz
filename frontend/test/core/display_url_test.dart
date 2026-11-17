import 'package:business_scraper_app/core/display_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('displayWebsite', () {
    test('drops scheme, www, trailing slash, query and fragment (tracking)', () {
      expect(displayWebsite('https://www.example-dental.com/?utm_source=gmb&utm_medium=organic'), 'example-dental.com');
      expect(displayWebsite('https://example.com/?gclid=abc123&fbclid=XYZ'), 'example.com');
      expect(displayWebsite('http://example.com/#contact'), 'example.com');
      expect(displayWebsite('https://www.example.com/'), 'example.com');
      expect(displayWebsite('https://www2.example.com'), 'example.com');
      expect(displayWebsite('https://user:secret@example.com/'), 'example.com');
    });

    test('unwraps Google and Facebook redirects to the target', () {
      expect(
        displayWebsite('https://www.google.com/url?q=https://www.joes-plumbing.ca/services/?utm_source=google&sa=D&ust=1'),
        'joes-plumbing.ca',
      );
      expect(displayWebsite('https://www.google.com/url?q=https%3A%2F%2Fexample.org%2F&sa=U'), 'example.org');
      expect(displayWebsite('https://google.co.uk/url?url=http://shop.example.co.uk/'), 'shop.example.co.uk');
      expect(displayWebsite('https://l.facebook.com/l.php?u=https%3A%2F%2Fshop.example.com%2F&h=AT0'), 'shop.example.com');
      // A redirect to a non-web target is not unwrapped.
      expect(displayWebsite('https://www.google.com/url?q=javascript:alert(1)', keepPath: true), 'google.com/url');
    });

    test('bare domains, subdomains, uppercase, ports and scheme-relative', () {
      expect(displayWebsite('example.com'), 'example.com');
      expect(displayWebsite('www.example.com/'), 'example.com');
      expect(displayWebsite('  EXAMPLE.COM/About  ', keepPath: true), 'example.com/About');
      expect(displayWebsite('HTTPS://WWW.EXAMPLE.COM'), 'example.com');
      expect(displayWebsite('https://shop.example.co.uk/'), 'shop.example.co.uk');
      expect(displayWebsite('example.com:8080/x', keepPath: true), 'example.com:8080/x');
      expect(displayWebsite('//example.com/doha', keepPath: true), 'example.com/doha');
      expect(displayWebsite('https://www.com'), 'www.com');
    });

    test('keeps short meaningful paths, drops long, deep and index-like ones', () {
      expect(displayWebsite('https://example.com/locations/doha/?utm_campaign=x', keepPath: true), 'example.com/locations/doha');
      expect(displayWebsite('https://example.com/index.html', keepPath: true), 'example.com');
      expect(displayWebsite('https://example.com/en/', keepPath: true), 'example.com');
      expect(displayWebsite('https://example.com/en/home', keepPath: true), 'example.com');
      expect(displayWebsite('https://example.com/en/menu', keepPath: true), 'example.com/en/menu');
      expect(displayWebsite('https://example.com/a/b/c', keepPath: true), 'example.com');
      expect(displayWebsite('https://example.com/${'x' * 300}?q=1', keepPath: true), 'example.com');
      expect(displayWebsite('https://example.com/%D9%85%D8%B7%D8%B9%D9%85', keepPath: true), 'example.com/مطعم');
    });

    test('social profiles keep the profile name', () {
      expect(displayWebsite('https://www.facebook.com/joesplumbing/?ref=page_internal'), 'facebook.com/joesplumbing');
      expect(displayWebsite('https://m.facebook.com/joesplumbing'), 'facebook.com/joesplumbing');
      expect(displayWebsite('https://www.facebook.com/profile.php?id=100064'), 'facebook.com');
      expect(displayWebsite('https://www.instagram.com/joes.plumbing/'), 'instagram.com/joes.plumbing');
      expect(displayWebsite('https://www.linkedin.com/company/acme-dental/about/'), 'linkedin.com/company/acme-dental');
    });

    test('IP addresses', () {
      expect(displayWebsite('http://192.168.1.10:8080/a?b=c', keepPath: true), '192.168.1.10:8080/a');
      expect(displayWebsite('http://10.0.0.1'), '10.0.0.1');
      expect(displayWebsite('http://999.1.1.1'), '');
      expect(displayWebsite('http://[2001:db8::1]/'), '[2001:db8::1]');
    });

    test('Unicode domains stay Unicode, punycode stays punycode', () {
      expect(displayWebsite('https://Bücher.DE/'), 'bücher.de');
      expect(displayWebsite('https://مثال.قطر/'), 'مثال.قطر');
      expect(displayWebsite('https://xn--mgbh0fb.xn--wgbl6a/'), 'xn--mgbh0fb.xn--wgbl6a');
    });

    test('empty, placeholders and garbage give an empty string', () {
      for (final v in [null, '', '   ', 'N/A', 'n/a', 'null', 'None', '-', 'not a url', 'example', 'www.exa mple.com', 'http://', 'https://.com']) {
        expect(displayWebsite(v), '', reason: '$v');
      }
    });

    test('non-web schemes give an empty string', () {
      for (final v in [
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'java\tscript:alert(1)',
        ' javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'mailto:info@example.com',
        'tel:+15550100',
        'ftp://example.com/file',
        'file:///etc/passwd',
        'vbscript:msgbox(1)',
      ]) {
        expect(displayWebsite(v), '', reason: v);
        expect(websiteLaunchUri(v), isNull, reason: v);
      }
    });
  });

  group('websiteLaunchUri', () {
    test('keeps the original value (query, tracking, redirect) and adds https when missing', () {
      expect(websiteLaunchUri('example.com/?utm_source=gmb')!.toString(), 'https://example.com/?utm_source=gmb');
      expect(websiteLaunchUri('http://example.com/a?b=1#c')!.toString(), 'http://example.com/a?b=1#c');
      const redirect = 'https://www.google.com/url?q=https://example.com/&sa=D';
      expect(websiteLaunchUri(redirect)!.toString(), redirect);
      expect(websiteLaunchUri('//example.com')!.toString(), 'https://example.com');
      expect(websiteLaunchUri('  https://example.com  ')!.toString(), 'https://example.com');
    });

    test('only http and https; garbage is null', () {
      expect(websiteLaunchUri('https://example.com')!.scheme, 'https');
      expect(websiteLaunchUri('http://example.com')!.scheme, 'http');
      expect(websiteLaunchUri(null), isNull);
      expect(websiteLaunchUri(''), isNull);
      expect(websiteLaunchUri('N/A'), isNull);
      expect(websiteLaunchUri('Call us'), isNull);
      expect(isOpenableWebsite('example.com'), isTrue);
      expect(isOpenableWebsite('nope'), isFalse);
    });

    test('very long URLs are accepted unchanged', () {
      final long = 'https://example.com/${List.filled(80, 'segment').join('/')}?utm_source=${'x' * 500}';
      expect(websiteLaunchUri(long)!.toString(), long);
      expect(displayWebsite(long), 'example.com');
    });
  });

  test('default shows the site name only (path kept only on social/profile hosts)', () {
    expect(
        displayWebsite('https://www.e2e-biz-3.example.com/landing/offer?utm_source=google&gclid=Cj0KCQiA'),
        'e2e-biz-3.example.com');
    expect(displayWebsite('https://example.com/locations/doha/'), 'example.com');
    expect(displayWebsite('example.com:8080/x'), 'example.com:8080');
    expect(displayWebsite('https://www.facebook.com/joesplumbing/?ref=page_internal'), 'facebook.com/joesplumbing');
  });
}
