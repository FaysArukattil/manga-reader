import 'package:html/dom.dart' as dom;
import 'site_adapter.dart';
import 'generic_site_adapter.dart';

/// Example adapter showing how a specific stubborn site can be handled with ~10 lines.
class ExampleSiteAdapter implements SiteAdapter {
  const ExampleSiteAdapter();

  @override
  bool matches(String host) => host.contains('example-manga.com');

  @override
  Future<ScrapedChapterResult> extract(dom.Document document, Uri pageUri) {
    // Custom container selector or custom logic
    return const GenericSiteAdapter().extract(document, pageUri);
  }
}
