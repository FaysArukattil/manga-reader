import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Ad / popup / tracker networks blocked inside the reader WebView.
/// One combined regex rule keeps per-request overhead (and battery) low.
const List<String> _blockedDomains = [
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.com',
  '2mdn.net',
  'adnxs.com',
  'adsrvr.org',
  'advertising.com',
  'amazon-adsystem.com',
  'criteo.com',
  'criteo.net',
  'pubmatic.com',
  'rubiconproject.com',
  'openx.net',
  'casalemedia.com',
  'smartadserver.com',
  'adform.net',
  'yieldmo.com',
  'zedo.com',
  'serving-sys.com',
  'taboola.com',
  'outbrain.com',
  'revcontent.com',
  'mgid.com',
  'adskeeper.com',
  'popads.net',
  'popcash.net',
  'propellerads.com',
  'onclickads.net',
  'adcash.com',
  'clickadu.com',
  'hilltopads.net',
  'exoclick.com',
  'exosrv.com',
  'juicyads.com',
  'trafficjunky.net',
  'trafficfactory.biz',
  'adsterra.com',
  'highperformanceformat.com',
  'profitablecpmrate.com',
  'effectivegatecpm.com',
  'a-ads.com',
  'ad-maven.com',
  'admaven.com',
  'bidvertiser.com',
  'ero-advertising.com',
  'tsyndicate.com',
  'yllix.com',
  'richads.com',
  'adsafeprotected.com',
  'moatads.com',
  'scorecardresearch.com',
  'disqusads.com',
];

const String _hideSelectors =
    'ins.adsbygoogle, .adsbygoogle, [id^="div-gpt-ad"], [id^="google_ads"], '
    'iframe[src*="doubleclick"], iframe[src*="googlesyndication"], '
    'iframe[src*="adsterra"], iframe[src*="exoclick"]';

List<ContentBlocker> buildContentBlockers() {
  final pattern =
      '.*(${_blockedDomains.map((d) => d.replaceAll('.', r'\.')).join('|')}).*';
  return [
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: pattern),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: '.*'),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector: _hideSelectors,
      ),
    ),
  ];
}
