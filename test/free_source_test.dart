import 'package:admin_api_key_manager/models/free_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the free-source directory', () {
    test('every entry has an id, a link to its limits and a check date', () {
      for (final source in kFreeSources) {
        expect(source.id, isNotEmpty, reason: source.name);
        expect(source.infoUrl, startsWith('https://'), reason: source.name);
        expect(source.verifiedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: source.name);
        expect(source.freeAllowance, isNotEmpty, reason: source.name);
      }
    });

    test('ids are unique — they are the search key and the saved filter', () {
      final ids = kFreeSources.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('anything that is not first-party is flagged for logging prompts', () {
      // A gateway resells someone else's model with your prompt attached; the
      // screen must never present one as safe without the warning.
      for (final source in kFreeSources) {
        if (source.kind != FreeSourceKind.provider) {
          expect(source.mayLogPrompts, isTrue, reason: source.name);
        }
      }
    });

    test('a base URL is a pasteable https endpoint without a trailing slash',
        () {
      for (final source in kFreeSources.where((s) => s.isOpenAiCompatible)) {
        expect(source.baseUrl, startsWith('https://'), reason: source.name);
        expect(source.baseUrl, isNot(endsWith('/')), reason: source.name);
      }
    });

    test('the daily-token pill is short enough for a chip', () {
      final nara = kFreeSources.firstWhere((s) => s.id == 'nararouter');
      expect(nara.dailyTokensLabel, '7M/day');
      final noQuota = kFreeSources.firstWhere((s) => s.id == 'groq');
      expect(noQuota.dailyTokensLabel, isNull);
    });
  });

  group('filterSources', () {
    test('an empty query keeps everything', () {
      expect(filterSources(kFreeSources).length, kFreeSources.length);
    });

    test('providersOnly drops the gateways', () {
      final only = filterSources(kFreeSources, providersOnly: true);
      expect(only, isNotEmpty);
      expect(only.every((s) => s.kind == FreeSourceKind.provider), isTrue);
      expect(only.length, lessThan(kFreeSources.length));
    });

    test('search matches name, id and free allowance, case-insensitively', () {
      expect(filterSources(kFreeSources, query: 'GROQ').single.id, 'groq');
      expect(filterSources(kFreeSources, query: 'nararouter').single.id,
          'nararouter');
      expect(
        filterSources(kFreeSources, query: 'tokens/day').single.id,
        'nararouter',
      );
      expect(filterSources(kFreeSources, query: 'no such thing'), isEmpty);
    });
  });
}
