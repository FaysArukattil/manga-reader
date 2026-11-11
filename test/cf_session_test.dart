import 'package:flutter_test/flutter_test.dart';
import 'package:shelfmark/services/scrape/cf_session.dart';

void main() {
  group('CfSession.looksLikeChallengeHtml', () {
    test('detects the real Cloudflare interstitial', () {
      const html = '<html><head><title>Just a moment...</title></head>'
          '<body><div id="challenge-running"></div>'
          '<script>window._cf_chl_opt={cType:"managed"};</script></body></html>';
      expect(CfSession.looksLikeChallengeHtml(html), isTrue);
    });

    test('does NOT flag a normal Cloudflare-protected chapter page', () {
      const html = '<html><head><title>Chapter 93 - Some Webtoon</title></head>'
          '<body><div class="reading-content"><img src="a.jpg"/><img src="b.jpg"/></div>'
          '<script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script>'
          '<div class="cf-turnstile"></div>'
          '<script src="https://challenges.cloudflare.com/turnstile/v0/api.js"></script>'
          '</body></html>';
      expect(CfSession.looksLikeChallengeHtml(html), isFalse);
    });

    test('cf-mitigated header marks a challenge response', () {
      expect(
        CfSession.isChallengeResponse(403, {'cf-mitigated': 'challenge'}, ''),
        isTrue,
      );
      expect(CfSession.isChallengeResponse(200, {}, '<html></html>'), isFalse);
    });
  });
}
