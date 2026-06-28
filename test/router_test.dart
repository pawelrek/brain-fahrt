import 'package:flutter_test/flutter_test.dart';
import 'package:slop/data/models/enums.dart';
import 'package:slop/pipeline/real/router.dart';

/// Bucket fixture mirroring the seed board: ids/names from `_seedBuckets`
/// (seed.dart) + description/keywords from AppDatabase.seedBucketMetadata.
const List<BucketInfo> kBuckets = [
  BucketInfo(
    id: 'devhub',
    name: 'devhub',
    isProject: true,
    description: 'developer tools project',
    keywords: 'build, deploy, api, release, feature, ci, dashboard',
  ),
  BucketInfo(
    id: 'webapp',
    name: 'Webapp',
    isProject: true,
    description: 'web app project',
    keywords: 'signup, crash, page, button, form, error',
  ),
  BucketInfo(
    id: 'general',
    name: 'General',
    isProject: true,
    description: 'general project notes',
    keywords: 'general, misc, note, other',
  ),
  BucketInfo(
    id: 'shopping',
    name: 'Shopping',
    isProject: false,
    description: 'things to buy',
    keywords: 'buy, groceries, store, food, milk, bread, supermarket, purchase',
  ),
  BucketInfo(
    id: 'todos',
    name: 'To-dos',
    isProject: false,
    description: 'tasks, chores and reminders',
    keywords:
        'task, todo, do, chore, remind, reminder, call, email, errand, pick up, give',
  ),
  BucketInfo(
    id: 'ideas',
    name: 'Ideas',
    isProject: false,
    description: 'ideas and thoughts',
    keywords: 'idea, maybe, thought, concept, brainstorm, what if',
  ),
];

void main() {
  group('summary cleaning', () {
    test('keeps a clean parsed title intact (firefox acceptance shape)', () {
      expect(
        cleanSummary('adding new user fails on firefox', kBuckets),
        'adding new user fails on firefox',
      );
    });

    test('strips "webapp bug:" prefix in two passes', () {
      expect(
        cleanSummary(
            'webapp bug: a bug with adding new user on firefox', kBuckets),
        'adding new user on firefox',
      );
    });

    test('keeps "improvement of compost mixing" intact', () {
      // The type-word rule requires a separator/connector; "of" is not one.
      expect(
        cleanSummary('improvement of compost mixing', kBuckets),
        'improvement of compost mixing',
      );
    });

    test('keeps "problem with adding new user" intact', () {
      // "problem" is deliberately NOT in the strip set.
      expect(
        cleanSummary('problem with adding new user', kBuckets),
        'problem with adding new user',
      );
    });

    test('never strips to empty', () {
      // Stripping the bucket name would leave '' (< 3 chars) — return original.
      expect(cleanSummary('webapp', kBuckets), 'webapp');
    });

    test('keeps "shopping cart icon misaligned" intact (no separator)', () {
      // A bucket word that is part of the content must survive: the leading
      // bucket-name strip requires a real separator or a type-word after it.
      expect(
        cleanSummary('shopping cart icon misaligned', kBuckets),
        'shopping cart icon misaligned',
      );
    });

    test('strips "webapp: login broken" with a real separator', () {
      expect(cleanSummary('webapp: login broken', kBuckets), 'login broken');
    });
  });

  group('parseClassify', () {
    test('parses right-to-left with | and -> inside the title', () {
      // The LAST '->' delimits the category and the LAST '|' the type, so a
      // title containing both stays intact.
      final r = Router.parseClassify(
          'fix a -> b mapping | bug -> webapp', kBuckets, 'fallback');
      expect(r.summary, 'fix a -> b mapping');
      expect(r.type, ItemType.bug);
      expect(r.bucketId, 'webapp');
    });

    test('fuzzy category rescue: misspelled project id', () {
      final r =
          Router.parseClassify('do the thing | bug -> webap', kBuckets, 'fb');
      expect(r.bucketId, 'webapp');
      expect(r.type, ItemType.bug);
      expect(r.summary, 'do the thing');
    });

    test('fuzzy category rescue: misspelled list id', () {
      final r =
          Router.parseClassify('buy milk | - -> shoping', kBuckets, 'fb');
      expect(r.bucketId, 'shopping');
      expect(r.type, isNull);
      expect(r.summary, 'buy milk');
    });

    test('anti-echo: summary equal to a bucket name falls back', () {
      final r = Router.parseClassify(
          'Webapp | bug -> webapp', kBuckets, 'the login is broken');
      expect(r.summary, 'the login is broken');
      expect(r.bucketId, 'webapp');
    });

    test('garbage line without -> falls back entirely', () {
      final r = Router.parseClassify(
          'sorry, I cannot help with that', kBuckets, 'fallback text');
      expect(r.summary, 'fallback text');
      expect(r.bucketId, isNull);
      expect(r.type, isNull);
    });
  });

  group('explicitTarget + stripRoutingPreamble', () {
    test('head-of-utterance "add to webapp list" yields match span + strip',
        () {
      const t = 'add to webapp list a bug with adding new user on firefox';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'webapp');
      expect(m.prepositionTokenIndex, 1);
      expect(stripRoutingPreamble(t, m),
          'a bug with adding new user on firefox');
    });

    test('mid-sentence "to X" is matched but not treated as preamble', () {
      const t = 'the login failure only applies to webapp somehow';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'webapp');
      expect(m.prepositionTokenIndex, greaterThan(3));
      expect(stripRoutingPreamble(t, m), t); // unchanged
    });

    test('mishear "web app" resolves to webapp', () {
      final m = Router.explicitTarget(
          'add it to web app the login is broken', kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'webapp');
    });

    test('"on" is not a routing preposition (locks current behavior)', () {
      expect(
          Router.explicitTarget('put milk on the shopping list', kBuckets),
          isNull);
    });

    test('never strips to nothing: "to webapp" alone returns original', () {
      const t = 'to webapp';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(stripRoutingPreamble(t, m!), t);
    });

    test('type-framing head strips: "bug report for dev hub …"', () {
      // 'bug'/'report' are framing, not content — the head (including the
      // spaced alias "dev hub") is safe to strip; the LLM/patch recovers the
      // type. (Codex round-2 B2.)
      const t = 'bug report for dev hub the build keeps failing';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'devhub');
      expect(m.matchedOnName, isTrue);
      expect(stripRoutingPreamble(t, m), 'the build keeps failing');
    });

    test('type-framing head strips: "idea for dev hub …"', () {
      const t = 'idea for dev hub we could add a dark mode toggle';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'devhub');
      expect(stripRoutingPreamble(t, m),
          'we could add a dark mode toggle');
    });

    test('keyword match routes but NEVER strips: "remind me to call mom"', () {
      // 'call' is a todos KEYWORD — routing may use it, but stripping through
      // it would destroy the leading content ("remind me to call" -> "mom").
      const t = 'remind me to call mom tomorrow';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'todos');
      expect(m.matchedOnName, isFalse);
      expect(stripRoutingPreamble(t, m), t); // full transcript reaches the LLM
    });

    test('non-filler head blocks strip: "buy supplies for shopping trip"', () {
      // Name match + head-of-utterance, but 'buy supplies' is content — the
      // strip must not cut it down to "trip tomorrow".
      const t = 'buy supplies for shopping trip tomorrow';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'shopping');
      expect(m.matchedOnName, isTrue);
      expect(stripRoutingPreamble(t, m), t); // full transcript reaches the LLM
    });

    test('non-filler head blocks strip: "fix the login for webapp …"', () {
      // 'fix'/'login' are not routing filler — "it crashes on tap" alone
      // would lose the actual subject of the note.
      const t = 'fix the login for webapp it crashes on tap';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.bucketId, 'webapp');
      expect(m.matchedOnName, isTrue);
      expect(stripRoutingPreamble(t, m), t); // full transcript reaches the LLM
    });

    test('all-filler head + name match still strips: "add to webapp list …"',
        () {
      const t = 'add to webapp list a bug with adding new user on firefox';
      final m = Router.explicitTarget(t, kBuckets);
      expect(m, isNotNull);
      expect(m!.matchedOnName, isTrue);
      expect(stripRoutingPreamble(t, m),
          'a bug with adding new user on firefox');
    });
  });

  group('typeHeuristic', () {
    test('broken → bug', () {
      expect(typeHeuristic('the login button is broken'), ItemType.bug);
    });

    test('framing head on the ORIGINAL transcript still yields the type', () {
      // route() runs the heuristic on the original transcript precisely
      // because the preamble strip removes 'bug report for …' (Codex r3 A1).
      expect(
          typeHeuristic(
              'bug report for dev hub the build keeps failing'),
          ItemType.bug);
    });

    test('could add → improvement', () {
      expect(typeHeuristic('we could add leg tracking'), ItemType.improvement);
    });

    test('problem → issue', () {
      expect(typeHeuristic('problem with the deploy'), ItemType.issue);
    });

    test('no keyword → null', () {
      expect(typeHeuristic('buy milk and eggs'), isNull);
    });
  });

  group('isGarbageTranscript', () {
    test('empty transcript is garbage', () {
      expect(isGarbageTranscript('', const Duration(seconds: 2)), isTrue);
    });

    test('sub-500ms audio is garbage', () {
      expect(
          isGarbageTranscript(
              'call mom', const Duration(milliseconds: 300)),
          isTrue);
    });

    test('repeated whisper markers are garbage', () {
      expect(
          isGarbageTranscript(
              '[BLANK_AUDIO] [BLANK_AUDIO]', const Duration(seconds: 2)),
          isTrue);
    });

    test('real bracketed note is NOT garbage', () {
      expect(isGarbageTranscript('(call mom)', const Duration(seconds: 2)),
          isFalse);
    });

    test('"ok" is NOT garbage (>=2 letters, 1s audio)', () {
      expect(
          isGarbageTranscript('ok', const Duration(seconds: 1)), isFalse);
    });
  });

  group('end-to-end firefox shape (no LLM)', () {
    test('add to webapp list a bug with adding new user on firefox', () {
      const transcript =
          'add to webapp list a bug with adding new user on firefox';

      final match = Router.explicitTarget(transcript, kBuckets);
      expect(match, isNotNull);
      expect(match!.bucketId, 'webapp');

      final llmInput = stripRoutingPreamble(transcript, match);
      expect(llmInput, 'a bug with adding new user on firefox');
      expect(llmInput.toLowerCase(), isNot(contains('webapp')));

      // Persona-v2-shaped model line for the stripped input.
      final parsed = Router.parseClassify(
          'adding new user fails on firefox | bug -> webapp',
          kBuckets,
          llmInput);
      final summary = cleanSummary(parsed.summary, kBuckets);

      expect(summary.toLowerCase().startsWith('webapp'), isFalse);
      expect(summary.toLowerCase().startsWith('bug'), isFalse);
      expect(summary.split(RegExp(r'\s+')).length, lessThanOrEqualTo(8));
      expect(parsed.type, ItemType.bug);
      expect(parsed.bucketId, 'webapp');
    });
  });
}
