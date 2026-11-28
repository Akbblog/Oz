import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/api_service.dart';
import '../../widgets/contact_form.dart';
import '../../widgets/country_flag_badge.dart';
import '../find/find_common.dart' show countryDisplayName;
import 'landing_kit.dart';

/// Public home page for visitors who are not signed in.
///
/// Every number on it is read from the live location data, and every claim
/// describes something the product does today.
class LandingScreen extends StatefulWidget {
  /// Injected in tests.
  final ApiService? api;
  const LandingScreen({super.key, this.api});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _Coverage {
  final List<MapEntry<String, int>> countries; // name -> regions
  final int regions;
  final int cities;
  const _Coverage(this.countries, this.regions, this.cities);

  /// Used until the live numbers arrive (and if they cannot be loaded).
  static const fallback = _Coverage([
    MapEntry('USA', 50), MapEntry('UK', 9), MapEntry('UAE', 7), MapEntry('KSA', 13),
    MapEntry('Australia', 8), MapEntry('Canada', 13), MapEntry('India', 34),
    MapEntry('Qatar', 8), MapEntry('Indonesia', 20), MapEntry('Malaysia', 16),
    MapEntry('Singapore', 1), MapEntry('China', 31), MapEntry('Finland', 11),
    MapEntry('Germany', 15), MapEntry('France', 13),
  ], 249, 0);
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  final _how = GlobalKey();
  final _features = GlobalKey();
  final _coverageKey = GlobalKey();
  final _faq = GlobalKey();
  final _contact = GlobalKey();

  _Coverage _coverage = _Coverage.fallback;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      _tick.value++;
      _scrolled.value = _scroll.offset > 12;
    });
    _loadCoverage();
  }

  Future<void> _loadCoverage() async {
    try {
      final data = await (widget.api ?? ApiService()).getLocationsSummary();
      final countries = <MapEntry<String, int>>[];
      var regions = 0, cities = 0;
      data.forEach((name, value) {
        final r = value is Map ? value['regions'] : null;
        if (r is! Map) return;
        countries.add(MapEntry(name, r.length));
        regions += r.length;
        for (final n in r.values) {
          if (n is num) cities += n.toInt();
        }
      });
      if (countries.isNotEmpty && mounted) {
        setState(() => _coverage = _Coverage(countries, regions, cities));
      }
    } catch (_) {
      // The page keeps its built-in figures.
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _scroll.dispose();
    _tick.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  void _go(String route) => Navigator.of(context).pushNamed(route);

  void _jump(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
        alignment: 0.04);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;
    final pad = width >= 1280 ? 40.0 : (width >= 700 ? 28.0 : 20.0);

    Widget section(Widget child, {Key? key, double top = 96, double bottom = 0}) =>
        Padding(
          key: key,
          padding: EdgeInsets.fromLTRB(pad, top, pad, bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: child,
            ),
          ),
        );

    return Scaffold(
      backgroundColor: LC.bg,
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: LT.font),
        child: RevealScope(
          tick: _tick,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        Positioned.fill(child: AuroraBackground(t: _loop)),
                        section(_hero(wide), top: wide ? 150 : 118, bottom: 30),
                      ],
                    ),
                    section(_stats(wide), top: 40),
                    section(_howItWorks(wide), key: _how),
                    section(_featureGrid(width), key: _features),
                    section(_coverageSection(), key: _coverageKey),
                    section(_faqSection(wide), key: _faq),
                    section(_contactSection(wide), key: _contact),
                    section(_finalCta(), top: 96, bottom: 56),
                    _footer(pad),
                  ],
                ),
              ),
              Positioned(top: 0, left: 0, right: 0, child: _navBar(wide, pad)),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- nav bar

  Widget _navBar(bool wide, double pad) {
    Widget link(String label, GlobalKey key) => TextButton(
          onPressed: () => _jump(key),
          style: TextButton.styleFrom(
            foregroundColor: LC.dim,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            textStyle: const TextStyle(
                fontFamily: LT.font, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          child: Text(label),
        );
    return ValueListenableBuilder<bool>(
      valueListenable: _scrolled,
      builder: (context, scrolled, child) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: scrolled ? 16 : 0, sigmaY: scrolled ? 16 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: scrolled ? const Color(0xCC0A0C0E) : Colors.transparent,
              border: Border(
                  bottom: BorderSide(
                      color: scrolled ? LC.border : Colors.transparent)),
            ),
            child: child,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: LC.accentDeep,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SvgPicture.asset('assets/logo_mark.svg',
                        colorFilter: const ColorFilter.mode(
                            Colors.white, BlendMode.srcIn)),
                  ),
                  if (MediaQuery.of(context).size.width >= 440) ...[
                    const SizedBox(width: 10),
                    const Text('Infinity Leads',
                        style: TextStyle(
                            color: LC.text,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2)),
                  ],
                  // Section links take whatever room is left and never push
                  // the buttons off the bar.
                  Expanded(
                    child: wide
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(left: 28),
                            child: Row(children: [
                              link('How it works', _how),
                              link('Features', _features),
                              link('Coverage', _coverageKey),
                              link('FAQ', _faq),
                              link('Contact', _contact),
                            ]),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TextButton(
                    onPressed: () => _go('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: LC.text,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(
                          fontFamily: LT.font,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(width: 6),
                  LButton('Find leads',
                      key: const Key('nav-find'), onPressed: () => _go('/find')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ hero

  Widget _hero(bool wide) {
    final size = MediaQuery.of(context).size.width;
    final h1 = size >= 1280 ? 66.0 : (size >= 980 ? 56.0 : (size >= 600 ? 46.0 : 37.0));
    final copy = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Reveal(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: LC.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: LC.accent.withValues(alpha: 0.28)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _PulseDot(t: _loop),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Local business leads in ${_coverage.countries.length} countries',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: LC.accent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        Reveal(
          delay: const Duration(milliseconds: 80),
          child: Column(
            crossAxisAlignment:
                wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Text('Find every business',
                  textAlign: wide ? TextAlign.left : TextAlign.center,
                  style: LT.display(h1)),
              GradientText('you could sell to.', style: LT.display(h1)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Reveal(
          delay: const Duration(milliseconds: 160),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Pick the cities, name the kind of business, and get a clean list with phone numbers, websites and emails, ready for Excel.',
              textAlign: wide ? TextAlign.left : TextAlign.center,
              style: LT.lead.copyWith(fontSize: size >= 600 ? 18 : 16),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Reveal(
          delay: const Duration(milliseconds: 240),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: [
              LButton('Find leads',
                  key: const Key('hero-find'),
                  large: true,
                  trailing: Icons.arrow_forward_rounded,
                  onPressed: () => _go('/find')),
              LButton('Create free account',
                  large: true, primary: false, onPressed: () => _go('/register')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Reveal(
          delay: const Duration(milliseconds: 320),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            children: const [
              _Tick('Look around without an account'),
              _Tick('See the cost before you start'),
            ],
          ),
        ),
      ],
    );

    final visual = Reveal(
      delay: const Duration(milliseconds: 200),
      dy: 40,
      child: HeroVisual(t: _loop),
    );

    if (!wide) {
      return Column(
        children: [
          copy,
          const SizedBox(height: 48),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520), child: visual),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 11, child: copy),
        const SizedBox(width: 40),
        Expanded(flex: 10, child: visual),
      ],
    );
  }

  // ----------------------------------------------------------------- stats

  Widget _stats(bool wide) {
    return _Shown(builder: (context, shown) {
      Widget stat(int value, String label, {String suffix = ''}) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUp(
                value: value,
                play: shown,
                suffix: suffix,
                style: const TextStyle(
                    fontFamily: LT.font,
                    color: LC.text,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: LT.small),
            ],
          );
      final items = <Widget>[
        stat(_coverage.countries.length, 'countries'),
        stat(_coverage.regions, 'states and regions'),
        if (_coverage.cities > 0) stat(_coverage.cities, 'cities to search'),
        stat(9, 'details per lead'),
      ];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        decoration: BoxDecoration(
          color: LC.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LC.border),
        ),
        child: wide
            ? Row(children: [for (final i in items) Expanded(child: i)])
            : Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 28,
                runSpacing: 26,
                children: [for (final i in items) SizedBox(width: 140, child: i)],
              ),
      );
    });
  }

  // ------------------------------------------------------------ how it works

  Widget _heading(String eyebrow, String title, String? sub) => Column(
        children: [
          Reveal(child: Text(eyebrow.toUpperCase(), style: LT.eyebrow)),
          const SizedBox(height: 12),
          Reveal(
            delay: const Duration(milliseconds: 60),
            child: Text(title, textAlign: TextAlign.center, style: LT.h2),
          ),
          if (sub != null) ...[
            const SizedBox(height: 12),
            Reveal(
              delay: const Duration(milliseconds: 120),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(sub, textAlign: TextAlign.center, style: LT.body),
              ),
            ),
          ],
          const SizedBox(height: 44),
        ],
      );

  Widget _howItWorks(bool wide) {
    Widget step(int n, IconData icon, String title, String text, Color color) =>
        Reveal(
          delay: Duration(milliseconds: 90 * n),
          child: HoverCard(
            glow: color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: color, size: 23),
                    ),
                    const Spacer(),
                    Text('0$n',
                        style: TextStyle(
                            fontFamily: LT.font,
                            color: Colors.white.withValues(alpha: 0.10),
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                  ],
                ),
                const SizedBox(height: 20),
                Text(title, style: LT.h3),
                const SizedBox(height: 8),
                Text(text, style: LT.body),
              ],
            ),
          ),
        );
    final steps = [
      step(1, Icons.place_outlined, 'Choose where',
          'Pick a country, then the states and cities you want. Select one city or hundreds.',
          LC.accent),
      step(2, Icons.storefront_outlined, 'Say who',
          'Type the kind of business: dentists, cafés, gyms, law firms. Set how many results you want per city.',
          LC.violet),
      step(3, Icons.table_view_outlined, 'Get the list',
          'The search runs on our servers. When it finishes, review the leads and download them as Excel or CSV.',
          LC.green),
    ];
    return Column(
      children: [
        _heading('How it works', 'From a city name to a call list in three steps',
            'No setup and nothing to install. It runs in your browser.'),
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  Expanded(child: steps[i]),
                ],
              ],
            ),
          )
        else
          Column(children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              steps[i],
            ],
          ]),
      ],
    );
  }

  // --------------------------------------------------------------- features

  Widget _featureGrid(double width) {
    const items = [
      (Icons.contact_phone_outlined, 'Contact details that matter',
          'Business name, phone, website, email when it is listed, address, category, city and a Google Maps link.', LC.accent),
      (Icons.travel_explore, 'Search many cities at once',
          'One search can cover a whole state or a hand-picked list of cities, with a result limit per city.', LC.violet),
      (Icons.cloud_done_outlined, 'Runs while you do other things',
          'Searches run on our servers. Close the tab and come back; your results are waiting.', LC.green),
      (Icons.receipt_long_outlined, 'Know the cost first',
          'You see the estimated credits before starting, and credits for results that were not delivered are returned.', LC.warm),
      (Icons.file_download_outlined, 'Excel and CSV export',
          'Download any search as a spreadsheet and bring it into your CRM, dialer or email tool.', LC.accent),
      (Icons.history_rounded, 'Every search kept',
          'Past searches stay in your account with their results, so you never pay for the same list twice.', LC.violet),
    ];
    final cols = width >= 1040 ? 3 : (width >= 660 ? 2 : 1);
    return Column(
      children: [
        _heading('Features', 'Built for people who sell to local businesses',
            'Agencies, freelancers and sales teams use it to fill their pipeline without copying listings by hand.'),
        LayoutBuilder(builder: (context, c) {
          const gap = 18.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: w,
                  child: Reveal(
                    delay: Duration(milliseconds: 70 * (i % cols)),
                    child: HoverCard(
                      glow: items[i].$4,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: cols == 1 ? 0 : 168),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(items[i].$1, color: items[i].$4, size: 26),
                          const SizedBox(height: 16),
                          Text(items[i].$2, style: LT.h3),
                          const SizedBox(height: 8),
                          Text(items[i].$3, style: LT.body),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  // --------------------------------------------------------------- coverage

  Widget _coverageSection() {
    return Column(
      children: [
        _heading(
            'Coverage',
            '${_coverage.countries.length} countries, down to the city',
            'Choose a country to see its states, provinces or regions and the cities inside them.'),
        Reveal(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _coverage.countries)
                _CountryChip(
                  name: c.key,
                  regions: c.value,
                  onTap: () => _go('/find'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- faq

  Widget _faqSection(bool wide) {
    final names = _coverage.countries.map((c) => countryDisplayName(c.key)).join(', ');
    final faqs = [
      ('Where do the leads come from?',
          'From public Google Business listings, the same ones you see on Google Maps, for the category and cities you choose.'),
      ('What do I get for each lead?',
          'Business name, phone number, website, email when the business lists one, address, category, city, state and a link to its Google Maps page.'),
      ('How does pricing work?',
          'Searches use credits. Before a search starts you see its estimated cost. If fewer results are delivered than estimated, the unused credits are returned to your balance.'),
      ('Do I need an account?',
          'You can browse locations and set up a search without one. To run it you need a free account; new accounts are reviewed before they are activated.'),
      ('Which countries are covered?', '$names.'),
      ('How do I get the data out?',
          'Open a finished search and download it as an Excel or CSV file. Your past searches stay in your account.'),
    ];
    final list = Column(
      children: [
        for (var i = 0; i < faqs.length; i++)
          Reveal(
            delay: Duration(milliseconds: 50 * i),
            child: _FaqItem(question: faqs[i].$1, answer: faqs[i].$2),
          ),
      ],
    );
    return Column(
      children: [
        _heading('FAQ', 'Questions people ask first', null),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: list),
      ],
    );
  }

  // ---------------------------------------------------------------- contact

  Widget _contactSection(bool wide) {
    Widget point(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: LC.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: LC.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: LT.h3.copyWith(fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(text, style: LT.body.copyWith(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(child: Text('CONTACT', style: LT.eyebrow)),
        const SizedBox(height: 12),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: const Text('Talk to us', style: LT.h2),
        ),
        const SizedBox(height: 12),
        Reveal(
          delay: const Duration(milliseconds: 120),
          child: const Text(
            'Have a question before you start, need a country we do not cover yet, or want help with your account? Send a message and a person will answer.',
            style: LT.body,
          ),
        ),
        const SizedBox(height: 28),
        Reveal(
          delay: const Duration(milliseconds: 180),
          child: Column(children: [
            point(Icons.mark_email_read_outlined, 'We reply by email',
                'Leave a phone or WhatsApp number as well if you would rather talk.'),
            point(Icons.handshake_outlined, 'Agencies and teams',
                'Tell us your volume and the countries you need.'),
            point(Icons.lock_outline, 'Your details stay with us',
                'They are used to answer your message and nothing else.'),
          ]),
        ),
      ],
    );
    final form = Reveal(
      delay: const Duration(milliseconds: 120),
      child: Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: LC.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LC.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 50,
                offset: const Offset(0, 24)),
          ],
        ),
        child: ContactForm(api: widget.api),
      ),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 28), form],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 9, child: Padding(padding: const EdgeInsets.only(top: 12), child: left)),
        const SizedBox(width: 48),
        Expanded(flex: 11, child: form),
      ],
    );
  }

  // ------------------------------------------------------------ cta + footer

  Widget _finalCta() {
    return Reveal(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 52),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: LC.accent.withValues(alpha: 0.25)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12313A), Color(0xFF131722), Color(0xFF1B1836)],
          ),
        ),
        child: Column(
          children: [
            Text('Your next customers are already listed.',
                textAlign: TextAlign.center,
                style: LT.h2.copyWith(
                    fontSize: MediaQuery.of(context).size.width >= 700 ? 36 : 27)),
            const SizedBox(height: 12),
            const Text('Set up a search in a minute and see what comes back.',
                textAlign: TextAlign.center, style: LT.lead),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                LButton('Find leads',
                    large: true,
                    trailing: Icons.arrow_forward_rounded,
                    onPressed: () => _go('/find')),
                LButton('Sign in',
                    large: true, primary: false, onPressed: () => _go('/login')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(double pad) {
    Widget link(String label, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: LC.mute,
            textStyle: const TextStyle(fontFamily: LT.font, fontSize: 13),
          ),
          child: Text(label),
        );
    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: LC.border))),
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180, minWidth: 1180),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Text('© ${DateTime.now().year} Infinity Leads', style: LT.small),
              Wrap(children: [
                link('Find leads', () => _go('/find')),
                link('Contact', () => _jump(_contact)),
                link('Privacy policy', () => _go('/privacy-policy')),
                link('Sign in', () => _go('/login')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- small pieces

class _Tick extends StatelessWidget {
  final String text;
  const _Tick(this.text);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: LC.green),
          const SizedBox(width: 7),
          Flexible(child: Text(text, style: LT.small.copyWith(color: LC.dim))),
        ],
      );
}

class _PulseDot extends StatelessWidget {
  final Animation<double> t;
  const _PulseDot({required this.t});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final p = (t.value * 6) % 1.0;
        return SizedBox(
          width: 12,
          height: 12,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 6 + p * 6,
              height: 6 + p * 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LC.accent.withValues(alpha: (1 - p) * 0.45)),
            ),
            Container(
              width: 6,
              height: 6,
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, color: LC.accent),
            ),
          ]),
        );
      },
    );
  }
}

/// Rebuilds with `shown = true` once scrolled into view.
class _Shown extends StatefulWidget {
  final Widget Function(BuildContext context, bool shown) builder;
  const _Shown({required this.builder});

  @override
  State<_Shown> createState() => _ShownState();
}

class _ShownState extends State<_Shown> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      onShown: (_) {
        if (mounted) setState(() => _shown = true);
      },
      child: widget.builder(context, _shown),
    );
  }
}

class _CountryChip extends StatefulWidget {
  final String name;
  final int regions;
  final VoidCallback onTap;
  const _CountryChip(
      {required this.name, required this.regions, required this.onTap});

  @override
  State<_CountryChip> createState() => _CountryChipState();
}

class _CountryChipState extends State<_CountryChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _hover ? LC.cardHi : LC.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _hover ? LC.accent.withValues(alpha: 0.5) : LC.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountryFlagBadge(countryName: widget.name, size: 18),
              const SizedBox(width: 10),
              Text(countryDisplayName(widget.name),
                  style: const TextStyle(
                      fontFamily: LT.font,
                      color: LC.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text('${widget.regions}', style: LT.small),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _open ? LC.cardHi : LC.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _open ? LC.borderHi : LC.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.question,
                          style: LT.h3.copyWith(fontSize: 16)),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.add_rounded,
                          color: _open ? LC.accent : LC.mute, size: 22),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10, right: 30),
                          child: Text(widget.answer, style: LT.body),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
