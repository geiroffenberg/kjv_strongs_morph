import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/admob_config.dart';
import '../models/verse.dart';
import '../models/note.dart';
import '../services/bible_service.dart';
import '../services/note_service.dart';
import 'note_editor.dart';
import 'notes_list_screen.dart';

class _MorphToken {
  final String label;
  final String explanation;

  const _MorphToken(this.label, this.explanation);
}

class _StrongsDisplayEntry {
  final String code;
  final bool isArticle;

  const _StrongsDisplayEntry({required this.code, this.isArticle = false});
}

class BibleReader extends StatefulWidget {
  const BibleReader({super.key});

  @override
  State<BibleReader> createState() => _BibleReaderState();
}

class _BibleReaderState extends State<BibleReader> {
  static const String _lastBookKey = 'last_read_book';
  static const String _lastOffsetKey = 'last_read_offset';
  static const String _hideStartupInfoKey = 'hide_startup_info';

  final BibleService _bibleService = BibleService();
  final NoteService _noteService = NoteService.instance;
  late Future<List<Verse>> _bibleFuture;
  List<String> _books = [];
  String? _selectedBook;
  int? _selectedChapter;
  List<Verse> _currentBookVerses = [];
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _chapterHeaderKeys = {};
  final Map<String, GlobalKey> _verseKeys = {};
  Timer? _savePositionTimer;
  Timer? _tipTimer;
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  bool _showLongPressTip = false;
  Map<String, dynamic> _strongsDictionary = {};
  bool _isStrongsDictionaryLoaded = false;
  bool _isLoadingStrongsDictionary = false;
  String? _restoredBook;
  double _restoredOffset = 0;
  double _textScale = 1.0;

  void _loadBannerAd() {
    final adUnitId = AdMobConfig.bannerAdUnitId;
    if (adUnitId.isEmpty) return;

    final banner = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    banner.load();
  }

  void _setTipVisibilityFromNotes() {
    final hasAnyNotes = _noteService.getAllNotes().isNotEmpty;
    if (hasAnyNotes) {
      _tipTimer?.cancel();
      if (_showLongPressTip && mounted) {
        setState(() {
          _showLongPressTip = false;
        });
      }
      return;
    }

    if (!_showLongPressTip && mounted) {
      setState(() {
        _showLongPressTip = true;
      });
    }

    _tipTimer?.cancel();
    _tipTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        _showLongPressTip = false;
      });
    });
  }

  GlobalKey _chapterKey(int chapter) {
    return _chapterHeaderKeys.putIfAbsent(chapter, () => GlobalKey());
  }

  GlobalKey _verseKey(int chapter, int verse) {
    return _verseKeys.putIfAbsent('$chapter:$verse', () => GlobalKey());
  }

  Future<void> _loadStrongsDictionary() async {
    if (_isStrongsDictionaryLoaded || _isLoadingStrongsDictionary) return;

    _isLoadingStrongsDictionary = true;
    try {
      final jsText = await rootBundle.loadString(
        'assets/strongs-greek-dictionary.js',
      );
      final firstBrace = jsText.indexOf('{');
      final lastBrace = jsText.lastIndexOf('}');
      if (firstBrace == -1 || lastBrace == -1 || firstBrace >= lastBrace) {
        return;
      }

      final jsonObject = jsText.substring(firstBrace, lastBrace + 1);
      final parsed = json.decode(jsonObject) as Map<String, dynamic>;
      _strongsDictionary = parsed;
      _isStrongsDictionaryLoaded = true;
    } catch (_) {
      _strongsDictionary = {};
      _isStrongsDictionaryLoaded = false;
    } finally {
      _isLoadingStrongsDictionary = false;
    }
  }

  Future<void> _showStartupInfoIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final hideInfo = prefs.getBool(_hideStartupInfoKey) ?? false;
    if (hideInfo || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      bool doNotShowAgain = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9DB),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2F6B33), Color(0xFF3E8146)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.auto_stories_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Welcome',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                if (doNotShowAgain) {
                                  await prefs.setBool(
                                    _hideStartupInfoKey,
                                    true,
                                  );
                                }
                                if (mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              },
                              icon: const Icon(Icons.close_rounded),
                              color: Colors.white,
                              visualDensity: VisualDensity.compact,
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(
                                  Icons.translate_rounded,
                                  size: 18,
                                  color: Color(0xFF2F6B33),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'This app shows New Testament text with Greek Strong\'s support.',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.4,
                                      color: Color(0xFF1E1E1E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(
                                  Icons.format_italic_rounded,
                                  size: 18,
                                  color: Color(0xFF2F6B33),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Words added by translators are shown in italics.',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.4,
                                      color: Color(0xFF1E1E1E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(
                                  Icons.touch_app_rounded,
                                  size: 18,
                                  color: Color(0xFF2F6B33),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tap a normal word to open Greek Strong\'s entries and morphology details.',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.4,
                                      color: Color(0xFF1E1E1E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF2F6B33,
                                ).withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF2F6B33,
                                  ).withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: doNotShowAgain,
                                    activeColor: const Color(0xFF2F6B33),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        doNotShowAgain = value ?? false;
                                      });
                                    },
                                  ),
                                  const Expanded(
                                    child: Text(
                                      'Do not show again',
                                      style: TextStyle(
                                        color: Color(0xFF1E1E1E),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2F6B33),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                            ),
                            onPressed: () async {
                              if (doNotShowAgain) {
                                await prefs.setBool(_hideStartupInfoKey, true);
                              }
                              if (mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            },
                            child: const Text('Start Reading'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    });
  }

  List<_MorphToken> _decodeMorphologyTokens(String? code) {
    if (code == null || code.isEmpty) return const [];

    const simpleLabels = <String, String>{
      'CONJ': 'Conjunction',
      'CONJ-N': 'Conjunction (Nestle variant)',
      'PREP': 'Preposition',
      'ADV': 'Adverb',
      'ADV-C': 'Comparative adverb',
      'ADV-S': 'Superlative adverb',
      'ADV-I': 'Interrogative adverb',
      'ADV-N': 'Adverb (Nestle variant)',
      'ADV-K': 'Adverb (Byzantine/TR variant)',
      'PRT': 'Particle',
      'PRT-N': 'Negative particle',
      'PRT-I': 'Interrogative particle',
      'HEB': 'Hebrew word',
      'ARAM': 'Aramaic word',
      'INJ': 'Interjection',
      'COND': 'Conditional particle',
      'COND-K': 'Conditional particle (Byzantine/TR variant)',
    };
    const simpleDetails = <String, String>{
      'CONJ': 'Connects words, phrases, or clauses.',
      'CONJ-N': 'A conjunction reading from the Nestle/critical text.',
      'PREP': 'Shows relationship such as place, time, or direction.',
      'ADV': 'Modifies a verb, adjective, or another adverb.',
      'ADV-C': 'An adverb in comparative form (more / -er).',
      'ADV-S': 'An adverb in superlative form (most / -est).',
      'ADV-I': 'An adverb used in questions (how, when, where).',
      'ADV-N': 'An adverb reading from the Nestle/critical text.',
      'ADV-K': 'An adverb reading from the Byzantine / Textus Receptus tradition.',
      'PRT': 'A small function word that adds nuance or structure.',
      'PRT-N': 'A particle used to express negation.',
      'PRT-I': 'A particle used in questions.',
      'HEB': 'A transliterated Hebrew word in the Greek text.',
      'ARAM': 'A transliterated Aramaic word in the Greek text.',
      'INJ': 'An exclamation or emotional expression.',
      'COND': 'Introduces a condition (often translated as if).',
      'COND-K': 'Conditional particle reading from the Byzantine / Textus Receptus tradition.',
    };

    if (simpleLabels.containsKey(code)) {
      return [
        _MorphToken(
          simpleLabels[code]!,
          simpleDetails[code] ?? 'Morphology detail for $code.',
        ),
      ];
    }

    final parts = code.split('-');
    final tokens = <_MorphToken>[];
    const posLabels = <String, String>{
      'N': 'Noun',
      'V': 'Verb',
      'A': 'Adjective',
      'T': 'Article',
      'P': 'Personal pronoun',
      'R': 'Relative pronoun',
      'C': 'Reciprocal pronoun',
      'D': 'Demonstrative pronoun',
      'K': 'Correlative pronoun',
      'I': 'Interrogative pronoun',
      'X': 'Indefinite pronoun',
      'Q': 'Correlative/interrogative pronoun',
      'F': 'Reflexive pronoun',
      'S': 'Possessive pronoun',
    };
    const posDetails = <String, String>{
      'N': 'A naming word (person, place, thing, or idea).',
      'V': 'An action or state-of-being word.',
      'A': 'Describes or qualifies a noun.',
      'T': 'The definite article (the).',
      'P': 'A pronoun referring to grammatical person.',
      'R': 'A pronoun linking to a previous word (who, which, that).',
      'C': 'A pronoun expressing mutual action (one another).',
      'D': 'A pronoun pointing out something (this, that).',
      'K': 'A pronoun pairing corresponding ideas.',
      'I': 'A pronoun used in direct questions.',
      'X': 'A non-specific pronoun (someone, something).',
      'Q': 'A pronoun with correlative/interrogative force.',
      'F': 'A pronoun referring back to the subject itself.',
      'S': 'A pronoun indicating possession.',
    };
    const caseLabels = <String, String>{
      'N': 'Nominative',
      'G': 'Genitive',
      'D': 'Dative',
      'A': 'Accusative',
      'V': 'Vocative',
    };
    const caseDetails = <String, String>{
      'N': 'Usually marks the subject of a clause.',
      'G': 'Often shows possession or source.',
      'D': 'Often marks indirect object, location, or means.',
      'A': 'Usually marks direct object or extent.',
      'V': 'Used for direct address.',
    };
    const numLabels = <String, String>{'S': 'Singular', 'P': 'Plural'};
    const numDetails = <String, String>{
      'S': 'Refers to one person or thing.',
      'P': 'Refers to more than one person or thing.',
    };
    const genLabels = <String, String>{
      'M': 'Masculine',
      'F': 'Feminine',
      'N': 'Neuter',
    };
    const genDetails = <String, String>{
      'M': 'Masculine grammatical gender.',
      'F': 'Feminine grammatical gender.',
      'N': 'Neuter grammatical gender.',
    };
    const tenseLabels = <String, String>{
      'P': 'Present',
      'I': 'Imperfect',
      'F': 'Future',
      'A': 'Aorist',
      'R': 'Perfect',
      'L': 'Pluperfect',
    };
    const tenseDetails = <String, String>{
      'P': 'Usually portrays ongoing action.',
      'I': 'Usually portrays ongoing action in past time.',
      'F': 'Usually portrays action as future.',
      'A': 'Often portrays action as a whole event.',
      'R': 'Action completed with continuing results.',
      'L': 'Past completed action with resulting state.',
    };
    const voiceLabels = <String, String>{
      'A': 'Active',
      'M': 'Middle',
      'P': 'Passive',
      'E': 'Middle/Passive',
      'D': 'Middle deponent',
      'O': 'Passive deponent',
      'N': 'Middle/Passive deponent',
      'Q': 'Active/Middle deponent',
    };
    const voiceDetails = <String, String>{
      'A': 'Subject performs the action.',
      'M': 'Subject participates in or benefits from the action.',
      'P': 'Subject receives the action.',
      'E': 'Form can function as middle or passive.',
      'D': 'Middle form with active meaning.',
      'O': 'Passive form with active meaning.',
      'N': 'Middle/passive form with active meaning.',
      'Q': 'Active or middle form used deponently.',
    };
    const moodLabels = <String, String>{
      'I': 'Indicative',
      'S': 'Subjunctive',
      'O': 'Optative',
      'M': 'Imperative',
      'N': 'Infinitive',
      'P': 'Participle',
    };
    const moodDetails = <String, String>{
      'I': 'States a fact or assertion.',
      'S': 'Expresses possibility, purpose, or contingency.',
      'O': 'Expresses wish or potentiality (rare in NT Greek).',
      'M': 'Expresses a command or request.',
      'N': 'Verbal noun form (to do).',
      'P': 'Verbal adjective form (doing / having done).',
    };
    const personLabels = <String, String>{
      '1': '1st person',
      '2': '2nd person',
      '3': '3rd person',
    };
    const personDetails = <String, String>{
      '1': 'Speaker or group including speaker.',
      '2': 'Addressee.',
      '3': 'Someone or something else.',
    };

    final pos = parts[0];
    final posLabel = posLabels[pos] ?? pos;
    tokens.add(
      _MorphToken(posLabel, posDetails[pos] ?? 'Part of speech: $posLabel.'),
    );

    if (pos == 'V' && parts.length >= 2) {
      var tvm = parts[1];
      if (tvm.startsWith('2')) {
        tokens.add(
          const _MorphToken(
            '2nd form',
            'An alternate (second) inflectional form in the lexical tradition.',
          ),
        );
        tvm = tvm.substring(1);
      }
      if (tvm.isNotEmpty) {
        final t = tvm[0];
        tokens.add(
          _MorphToken(
            tenseLabels[t] ?? t,
            tenseDetails[t] ?? 'Tense code: $t.',
          ),
        );
      }
      if (tvm.length >= 2) {
        final v = tvm[1];
        tokens.add(
          _MorphToken(
            voiceLabels[v] ?? v,
            voiceDetails[v] ?? 'Voice code: $v.',
          ),
        );
      }
      if (tvm.length >= 3) {
        final m = tvm[2];
        tokens.add(
          _MorphToken(moodLabels[m] ?? m, moodDetails[m] ?? 'Mood code: $m.'),
        );
      }
      if (parts.length >= 3) {
        final pn = parts[2];
        if (pn.isNotEmpty && personLabels.containsKey(pn[0])) {
          final p = pn[0];
          tokens.add(
            _MorphToken(
              personLabels[p] ?? p,
              personDetails[p] ?? 'Person code: $p.',
            ),
          );
          if (pn.length >= 2) {
            final n = pn[1];
            tokens.add(
              _MorphToken(
                numLabels[n] ?? n,
                numDetails[n] ?? 'Number code: $n.',
              ),
            );
          }
        } else {
          if (pn.isNotEmpty) {
            final c = pn[0];
            tokens.add(
              _MorphToken(
                caseLabels[c] ?? c,
                caseDetails[c] ?? 'Case code: $c.',
              ),
            );
          }
          if (pn.length >= 2) {
            final n = pn[1];
            tokens.add(
              _MorphToken(
                numLabels[n] ?? n,
                numDetails[n] ?? 'Number code: $n.',
              ),
            );
          }
          if (pn.length >= 3) {
            final g = pn[2];
            tokens.add(
              _MorphToken(
                genLabels[g] ?? g,
                genDetails[g] ?? 'Gender code: $g.',
              ),
            );
          }
        }
      }
      // Trailing variant suffixes on verbs, e.g. V-AAI-3P-ATT (Attic form).
      for (var i = 3; i < parts.length; i++) {
        final v = parts[i];
        const vLabels = <String, String>{
          'ATT': 'Attic form',
          'ABB': 'Abbreviated form',
          'N': 'Nestle variant',
          'K': 'Byzantine/TR variant',
        };
        const vDetails = <String, String>{
          'ATT': 'An Attic Greek dialectal form preserved in the New Testament text.',
          'ABB': 'A shortened or abbreviated written form.',
          'N': 'Reading from the Nestle/critical Greek text.',
          'K': 'Reading from the Byzantine / Textus Receptus tradition.',
        };
        final label = vLabels[v];
        if (label != null) {
          tokens.add(
            _MorphToken(label, vDetails[v] ?? 'Variant code: $v.'),
          );
        }
      }
    } else if (parts.length >= 2) {
      var cng = parts[1];

      // Indeclinable / non-standard forms used in this dataset:
      //   N-LI  = letter (indeclinable)
      //   N-OI  = other indeclinable
      //   N-PRI = proper name (indeclinable)
      //   A-NUI = numeral (indeclinable)
      const indeclLabels = <String, String>{
        'LI': 'Letter (indeclinable)',
        'OI': 'Indeclinable',
        'PRI': 'Proper name (indeclinable)',
        'NUI': 'Numeral (indeclinable)',
      };
      const indeclDetails = <String, String>{
        'LI': 'A Greek letter used as a label or number; does not inflect.',
        'OI': 'An indeclinable form that does not change for case, number, or gender.',
        'PRI': 'A proper name that does not inflect (often transliterated from Hebrew or Aramaic).',
        'NUI': 'A cardinal number written out as a word; does not inflect.',
      };
      if (indeclLabels.containsKey(cng)) {
        tokens.add(
          _MorphToken(indeclLabels[cng]!, indeclDetails[cng]!),
        );
        cng = '';
      } else {
        // Possessive pronouns (S-*) use a 2-character person + possessor-number
        // prefix before the standard case/number/gender triplet, e.g.
        //   S-1SNSM = 1st person singular possessor, nominative singular masculine possessed.
        if (pos == 'S' &&
            cng.length >= 2 &&
            personLabels.containsKey(cng[0]) &&
            numLabels.containsKey(cng[1])) {
          final p = cng[0];
          final pn = cng[1];
          tokens.add(
            _MorphToken(
              '${personLabels[p]} ${numLabels[pn]!.toLowerCase()} possessor',
              'Possessor is ${personDetails[p]?.toLowerCase() ?? 'person $p.'} '
                  '${numDetails[pn]?.toLowerCase() ?? ''}'.trim(),
            ),
          );
          cng = cng.substring(2);
        } else {
          // Personal (P-) and reflexive (F-) pronouns may be prefixed with a
          // single person digit, e.g. F-2APM (2nd person accusative plural masculine)
          // or P-1NS (1st person nominative singular).
          const pronounsWithPerson = {'P', 'F'};
          if (pronounsWithPerson.contains(pos) &&
              cng.isNotEmpty &&
              personLabels.containsKey(cng[0])) {
            final p = cng[0];
            tokens.add(
              _MorphToken(
                personLabels[p] ?? p,
                personDetails[p] ?? 'Person code: $p.',
              ),
            );
            cng = cng.substring(1);
          }
        }
      }

      if (cng.isNotEmpty) {
        final c = cng[0];
        tokens.add(
          _MorphToken(caseLabels[c] ?? c, caseDetails[c] ?? 'Case code: $c.'),
        );
      }
      if (cng.length >= 2) {
        final n = cng[1];
        tokens.add(
          _MorphToken(numLabels[n] ?? n, numDetails[n] ?? 'Number code: $n.'),
        );
      }
      if (cng.length >= 3) {
        final g = cng[2];
        tokens.add(
          _MorphToken(genLabels[g] ?? g, genDetails[g] ?? 'Gender code: $g.'),
        );
      }

      // Trailing variant / qualifier suffixes (parts[2] and beyond).
      const variantLabels = <String, String>{
        'C': 'Comparative',
        'S': 'Superlative',
        'N': 'Nestle variant',
        'K': 'Byzantine/TR variant',
        'ATT': 'Attic form',
        'ABB': 'Abbreviated form',
        'I': 'Interrogative',
      };
      const variantDetails = <String, String>{
        'C': 'Compares two or more things (more / -er).',
        'S': 'Expresses the highest degree (most / -est).',
        'N': 'Reading from the Nestle/critical Greek text.',
        'K': 'Reading from the Byzantine / Textus Receptus tradition.',
        'ATT': 'An Attic Greek dialectal form preserved in the New Testament text.',
        'ABB': 'A shortened or abbreviated written form.',
        'I': 'Carries an interrogative (question) force.',
      };
      for (var i = 2; i < parts.length; i++) {
        final v = parts[i];
        final label = variantLabels[v];
        if (label != null) {
          tokens.add(
            _MorphToken(label, variantDetails[v] ?? 'Variant code: $v.'),
          );
        }
      }
    }

    return tokens;
  }

  Future<void> _showMorphTermExplanation(_MorphToken token) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9DB),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F6B33).withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2F6B33), Color(0xFF3A7C41)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            token.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Text(
                      token.explanation,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFF2F6B33),
                          backgroundColor: const Color(
                            0xFF2F6B33,
                          ).withValues(alpha: 0.13),
                        ),
                        child: const Text('Got it'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _selectPrimaryStrongsCode(List<String> codes) {
    if (codes.length <= 1) return codes.first;

    // Prefer a non-article lexeme for combined entries like [G3588, G80].
    final nonArticleCodes = codes.where((code) => code != 'G3588').toList();
    if (nonArticleCodes.isNotEmpty) {
      return nonArticleCodes.last;
    }

    return codes.last;
  }

  List<_MorphToken> _morphTokensForSelectedCode(
    Word word,
    String selectedCode,
  ) {
    if (word.m == null || word.m!.isEmpty) return const [];
    if (word.s.length <= 1) return _decodeMorphologyTokens(word.m);

    final morph = word.m!;
    final selectedIsFirstCode =
        word.s.isNotEmpty && word.s.first == selectedCode;

    // In this dataset, T-* often tags the article in a two-code phrase.
    // If we focused a later non-article code, suppress mismatched morphology chips.
    if (morph.startsWith('T-') && !selectedIsFirstCode) {
      return const [];
    }

    return _decodeMorphologyTokens(word.m);
  }

  bool _isMorphSuppressedForSelectedCode(Word word, String selectedCode) {
    if (word.s.length <= 1) return false;
    if (!(word.m?.startsWith('T-') ?? false)) return false;
    return word.s.first != selectedCode;
  }

  List<_StrongsDisplayEntry> _buildStrongsDisplayEntries(Word word) {
    if (word.s.isEmpty) return const [];

    final primaryCode = _selectPrimaryStrongsCode(word.s);
    final entries = <_StrongsDisplayEntry>[
      _StrongsDisplayEntry(code: primaryCode),
    ];

    final hasArticle = word.s.contains('G3588');
    if (hasArticle && primaryCode != 'G3588') {
      entries.add(const _StrongsDisplayEntry(code: 'G3588', isArticle: true));
    }

    return entries;
  }

  String _studyWordLabel(Word word) {
    final raw = word.w.trim();
    if (raw.isEmpty) return word.w;

    final lower = raw.toLowerCase();

    // Mark the definite article "the" when it is baked into the English
    // lexeme with no dedicated G3588 card. If G3588 is present as its own
    // Strong's code, it gets its own article card and the prefix would be
    // redundant (e.g. avoids "(the) of liberty").
    if (lower.startsWith('the ') && raw.length > 4 && !word.s.contains('G3588')) {
      return '(the) ${raw.substring(4)}';
    }

    // Greek has no indefinite article, so KJV's "a" / "an" is supplied by the
    // translator. Mark it so readers know it is not in the Greek.
    if (lower.startsWith('a ') && raw.length > 2) {
      return '(a) ${raw.substring(2)}';
    }
    if (lower.startsWith('an ') && raw.length > 3) {
      return '(an) ${raw.substring(3)}';
    }

    return raw;
  }

  Widget _buildStrongsDefinitionCard({
    required String code,
    required Map<String, dynamic>? entryMap,
    required List<_MorphToken> morphTokens,
    required bool hasSuppressedArticleMorph,
    required bool isArticle,
  }) {
    final sectionTitle = isArticle ? 'Article Entry' : 'Lexical Entry';
    final sectionIcon = isArticle
        ? Icons.text_fields_rounded
        : Icons.menu_book_rounded;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFF2F6B33).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  sectionIcon,
                  size: 15,
                  color: const Color(0xFF2F6B33),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                sectionTitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  letterSpacing: 0.3,
                  color: Color(0xFF2F6B33),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: const Color(0xFF2F6B33).withValues(alpha: 0.2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                code,
                style: const TextStyle(
                  color: Color(0xFF2F6B33),
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isArticle) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F6B33).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'ARTICLE',
                    style: TextStyle(
                      color: Color(0xFF2F6B33),
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (entryMap != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if ((entryMap['lemma'] ?? '').toString().isNotEmpty)
                  Flexible(
                    child: Text(
                      entryMap['lemma'].toString(),
                      style: const TextStyle(
                        fontSize: 19,
                        color: Color(0xFF2F6B33),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if ((entryMap['lemma'] ?? '').toString().isNotEmpty &&
                    (entryMap['translit'] ?? '').toString().isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '·',
                      style: TextStyle(color: Colors.black38, fontSize: 18),
                    ),
                  ),
                if ((entryMap['translit'] ?? '').toString().isNotEmpty)
                  Flexible(
                    child: Text(
                      entryMap['translit'].toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (morphTokens.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2F6B33).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF2F6B33).withValues(alpha: 0.26),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final token in morphTokens)
                    Material(
                      color: const Color(0xFF2F6B33).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showMorphTermExplanation(token),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            token.label,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF2F6B33),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (hasSuppressedArticleMorph) ...[
            const SizedBox(height: 10),
            const Text(
              'Morphology in this phrase is tagged for the article; this card focuses on the lexical word.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 12),
          if (entryMap == null)
            Text(
              'No entry found for $code.',
              style: const TextStyle(color: Colors.black54),
            )
          else ...[
            if ((entryMap['strongs_def'] ?? '').toString().trim().isNotEmpty)
              Text(
                entryMap['strongs_def'].toString().trim(),
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            if ((entryMap['kjv_def'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF444444),
                  ),
                  children: [
                    const TextSpan(
                      text: 'KJV uses:  ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    TextSpan(text: entryMap['kjv_def'].toString().trim()),
                  ],
                ),
              ),
            ],
            if ((entryMap['derivation'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                entryMap['derivation'].toString().trim(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black45,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _showStrongsEntry(Word word) async {
    if (word.s.isEmpty) return;
    final displayEntries = _buildStrongsDisplayEntries(word);
    if (displayEntries.isEmpty) return;
    final headerCodeLabel = displayEntries.map((e) => e.code).join(' + ');
    final studyLabel = _studyWordLabel(word);
    // Only show the "(the)" legend when the article is embedded in the English
    // text with no dedicated G3588 card (otherwise the article has its own card).
    final textStartsWithThe =
        word.w.toLowerCase().trim().startsWith('the ') && word.w.length > 4;
    final showsArticleMarker = textStartsWithThe && !word.s.contains('G3588');

    if (!_isStrongsDictionaryLoaded) {
      await _loadStrongsDictionary();
    }

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFF9DB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header bar
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF2F6B33),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Text(
                        headerCodeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // English word/phrase
                        Text(
                          studyLabel,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (showsArticleMarker)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Words in parentheses such as (the), (a), or (an) mark articles supplied in English that are not separate words in the Greek.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (displayEntries.length > 1)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'This phrase includes multiple original Greek terms.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        for (final display in displayEntries)
                          _buildStrongsDefinitionCard(
                            code: display.code,
                            entryMap:
                                _strongsDictionary[display.code]
                                    is Map<String, dynamic>
                                ? _strongsDictionary[display.code]
                                      as Map<String, dynamic>
                                : null,
                            morphTokens: _morphTokensForSelectedCode(
                              word,
                              display.code,
                            ),
                            hasSuppressedArticleMorph:
                                _isMorphSuppressedForSelectedCode(
                                  word,
                                  display.code,
                                ),
                            isArticle: display.isArticle,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerseText(Verse verse, TextStyle baseStyle, TextStyle refStyle) {
    final children = <Widget>[
      Text('${verse.chapter}:${verse.verse} ', style: refStyle),
    ];

    for (final word in verse.words) {
      final text = word.p != null ? '${word.w}${word.p} ' : '${word.w} ';
      final style = word.a
          ? baseStyle.copyWith(fontStyle: FontStyle.italic)
          : baseStyle;

      if (word.a || word.s.isEmpty) {
        children.add(Text(text, style: style));
      } else {
        children.add(
          GestureDetector(
            onTap: () => _showStrongsEntry(word),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(text, style: style),
            ),
          ),
        );
      }
    }

    if (_noteService.hasNote(verse.bookName, verse.chapter, verse.verse)) {
      children.add(
        const Text(
          '*',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadStrongsDictionary();
    _showStartupInfoIfNeeded();
    _scrollController.addListener(_onScrollChanged);
    _noteService.loadNotes().then((_) {
      if (!mounted) return;
      setState(() {});
      _setTipVisibilityFromNotes();
    });
    _bibleFuture = _restoreReadingPosition()
        .then((_) {
          return _bibleService.loadBible();
        })
        .then((verses) {
          _books = _bibleService.getUniqueBooks();
          if (_selectedBook == null && _books.isNotEmpty) {
            _selectedBook =
                (_restoredBook != null && _books.contains(_restoredBook))
                ? _restoredBook
                : _books.first;
            _loadBook(_selectedBook!);
            if (_restoredOffset > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _scrollController.hasClients) {
                  _scrollController.jumpTo(
                    _restoredOffset.clamp(
                      0,
                      _scrollController.position.maxScrollExtent,
                    ),
                  );
                }
              });
            }
          }
          return verses;
        });
  }

  Future<void> _restoreReadingPosition() async {
    final prefs = await SharedPreferences.getInstance();
    _restoredBook = prefs.getString(_lastBookKey);
    _restoredOffset = prefs.getDouble(_lastOffsetKey) ?? 0;
  }

  void _onScrollChanged() {
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer(const Duration(milliseconds: 400), () {
      _saveReadingPosition();
    });
  }

  Future<void> _saveReadingPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedBook = _selectedBook;
    if (selectedBook != null && selectedBook.isNotEmpty) {
      await prefs.setString(_lastBookKey, selectedBook);
    }
    if (_scrollController.hasClients) {
      await prefs.setDouble(_lastOffsetKey, _scrollController.offset);
    }
  }

  void _loadBook(String book) {
    setState(() {
      _selectedBook = book;
      _chapterHeaderKeys.clear();
      _verseKeys.clear();
      _currentBookVerses = _bibleService
          .getAllVerses()
          .where((v) => v.bookName == book)
          .toList();
      final chapters = _bibleService.getChaptersForBook(book);
      _selectedChapter = chapters.isNotEmpty ? chapters.first : null;
    });
  }

  void _jumpToChapter(int chapter) {
    final key = _chapterKey(chapter);
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _jumpToVerse(String bookName, int chapter, int verse) {
    if (_selectedBook != bookName) {
      _loadBook(bookName);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animateToVerse(chapter, verse);
      });
      return;
    }
    _animateToVerse(chapter, verse);
  }

  void _animateToVerse(int chapter, int verse) {
    final key = _verseKey(chapter, verse);
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showNoteEditor(Verse verse) async {
    final existingNote = await _noteService.getNote(
      verse.bookName,
      verse.chapter,
      verse.verse,
    );

    if (mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoteEditor(
            bookName: verse.bookName,
            chapter: verse.chapter,
            verse: verse.verse,
            verseText: verse.plainText,
            existingNote: existingNote,
          ),
          fullscreenDialog: true,
        ),
      );

      if (result == true && mounted) {
        setState(() {});
        _setTipVisibilityFromNotes();
      }
    }
  }

  void _toggleTextSize() {
    setState(() {
      if (_textScale < 1.1) {
        _textScale = 1.2;
      } else if (_textScale < 1.25) {
        _textScale = 1.35;
      } else {
        _textScale = 1.0;
      }
    });
  }

  Future<void> _openNotes() async {
    final selectedNote = await Navigator.push<Note>(
      context,
      MaterialPageRoute(builder: (_) => const NotesListScreen()),
    );

    if (selectedNote != null && mounted) {
      _jumpToVerse(
        selectedNote.bookName,
        selectedNote.chapter,
        selectedNote.verse,
      );
    }
  }

  void _showSearchPane() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF9DB),
      builder: (context) {
        final allVerses = _bibleService.getAllVerses();
        String query = '';
        List<Verse> results = [];

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: const Color(0xFF2F6B33),
                    child: const Text(
                      'Search',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Search verses',
                            hintText: 'Type any word or phrase',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              query = value.trim().toLowerCase();
                              if (query.isEmpty) {
                                results = [];
                              } else {
                                results = allVerses
                                    .where(
                                      (v) => v.plainText.toLowerCase().contains(
                                        query,
                                      ),
                                    )
                                    .take(100)
                                    .toList();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        if (query.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'Start typing to search the New Testament.',
                            ),
                          )
                        else if (results.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('No verses found.'),
                          )
                        else
                          SizedBox(
                            height: 380,
                            child: ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (context, index) {
                                final verse = results[index];
                                return ListTile(
                                  title: Text(
                                    '${verse.bookName} ${verse.chapter}:${verse.verse}',
                                  ),
                                  subtitle: Text(
                                    verse.plainText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _jumpToVerse(
                                      verse.bookName,
                                      verse.chapter,
                                      verse.verse,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showInfoPane() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        Widget sectionCard({
          required IconData icon,
          required String title,
          required List<String> lines,
        }) {
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F6B33).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 15,
                        color: const Color(0xFF2F6B33),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF2F6B33),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final line in lines) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: Color(0xFF2F6B33),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 14.8,
                            height: 1.4,
                            color: Color(0xFF1E1E1E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                ],
              ],
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF9DB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F6B33).withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2F6B33), Color(0xFF3E8146)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'About This App',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionCard(
                            icon: Icons.explore_rounded,
                            title: 'Overview',
                            lines: const [
                              'Immersive New Testament reading with integrated Greek Strong\'s lookup, morphology help, and verse notes.',
                            ],
                          ),
                          sectionCard(
                            icon: Icons.library_books_rounded,
                            title: 'Text and Source',
                            lines: const [
                              'Uses the New Testament KJV text with Greek Strong\'s references in the source data.',
                              'Words added by translators may appear in italics.',
                            ],
                          ),
                          sectionCard(
                            icon: Icons.menu_book_rounded,
                            title: 'Word Study Features',
                            lines: const [
                              'Tap a normal word to open its Greek Strong\'s panel.',
                              'Some phrases include two entries (lexical word + article) shown as separate cards.',
                              'Morphology appears as clickable chips.',
                              'Tap any morphology term chip for a quick explanation.',
                            ],
                          ),
                          sectionCard(
                            icon: Icons.travel_explore_rounded,
                            title: 'Reading and Navigation',
                            lines: const [
                              'Use the book and chapter controls to jump anywhere in the New Testament.',
                              'Use Search to find words or phrases across verses.',
                              'Use Text to adjust reading size.',
                              'Your reading position is automatically remembered.',
                            ],
                          ),
                          sectionCard(
                            icon: Icons.sticky_note_2_rounded,
                            title: 'Notes',
                            lines: const [
                              'Long-press a verse to add or edit a note.',
                              'Use Notes to browse and reopen your saved notes by reference.',
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topActionButton({
    required Widget child,
    required String tooltip,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF2F6B33),
              border: Border(
                right: showDivider
                    ? const BorderSide(color: Colors.white24, width: 1)
                    : BorderSide.none,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _savePositionTimer?.cancel();
    _tipTimer?.cancel();
    _saveReadingPosition();
    _bannerAd?.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Verse>>(
      future: _bibleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('New Testament Reader')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('New Testament Reader')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('New Testament Reader')),
            body: const Center(child: Text('No verses found')),
          );
        }

        final chapters = _selectedBook == null
            ? <int>[]
            : _bibleService.getChaptersForBook(_selectedBook!);

        return Scaffold(
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    _topActionButton(
                      tooltip: 'Notes',
                      onTap: _openNotes,
                      child: const Icon(
                        Icons.sticky_note_2_outlined,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    _topActionButton(
                      tooltip: 'Search',
                      onTap: _showSearchPane,
                      child: const Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    _topActionButton(
                      tooltip: 'Text size',
                      onTap: _toggleTextSize,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'A',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'A',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _topActionButton(
                      tooltip: 'Info',
                      onTap: _showInfoPane,
                      showDivider: false,
                      child: const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ),
              // Book Selection
              Container(
                color: const Color(0xFFFFF9DB),
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBook,
                          dropdownColor: const Color(0xFFFFF9DB),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          items: _books
                              .map(
                                (book) => DropdownMenuItem(
                                  value: book,
                                  child: Text(
                                    book,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (book) {
                            if (book != null) {
                              _loadBook(book);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final firstChapter = _selectedChapter;
                                if (firstChapter != null) {
                                  _jumpToChapter(firstChapter);
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedChapter,
                          dropdownColor: const Color(0xFFFFF9DB),
                          hint: const Text(
                            'Chapter',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          items: chapters
                              .map(
                                (chapter) => DropdownMenuItem<int>(
                                  value: chapter,
                                  child: Text(
                                    'Chapter $chapter',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (chapter) {
                            if (chapter == null) return;
                            setState(() {
                              _selectedChapter = chapter;
                            });
                            _jumpToChapter(chapter);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Bible Text - Continuous scroll
              if (_showLongPressTip)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.blue.withValues(alpha: 0.05),
                  child: Text(
                    'Tip: Long-press a verse to add or edit a note.',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              Expanded(
                child: _currentBookVerses.isEmpty
                    ? const Center(child: Text('No verses found'))
                    : ListView.builder(
                        controller: _scrollController,
                        cacheExtent: 999999,
                        padding: const EdgeInsets.all(16),
                        itemCount: _currentBookVerses.length,
                        itemBuilder: (context, index) {
                          final verse = _currentBookVerses[index];
                          final prevVerse = index > 0
                              ? _currentBookVerses[index - 1]
                              : null;
                          final isNewChapter =
                              prevVerse == null ||
                              prevVerse.chapter != verse.chapter;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Chapter Header
                              if (isNewChapter) ...[
                                Container(
                                  key: _chapterKey(verse.chapter),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 0,
                                    ),
                                    child: Text(
                                      'Chapter ${verse.chapter}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[700],
                                            fontSize:
                                                (Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.fontSize ??
                                                    16) *
                                                _textScale,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                              // Verse
                              GestureDetector(
                                key: _verseKey(verse.chapter, verse.verse),
                                onLongPress: () => _showNoteEditor(verse),
                                child: Padding(
                                  padding: EdgeInsets.zero,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          _noteService.hasNote(
                                            verse.bookName,
                                            verse.chapter,
                                            verse.verse,
                                          )
                                          ? Colors.yellow[50]
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border:
                                          _noteService.hasNote(
                                            verse.bookName,
                                            verse.chapter,
                                            verse.verse,
                                          )
                                          ? Border.all(
                                              color: Colors.yellow[200]!,
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    padding:
                                        _noteService.hasNote(
                                          verse.bookName,
                                          verse.chapter,
                                          verse.verse,
                                        )
                                        ? const EdgeInsets.all(8)
                                        : EdgeInsets.zero,
                                    child: _buildVerseText(
                                      verse,
                                      TextStyle(
                                        color: Colors.black,
                                        fontSize:
                                            ((Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.fontSize ??
                                                16) *
                                            _textScale),
                                      ),
                                      TextStyle(
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize:
                                            ((Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.fontSize ??
                                                16) *
                                            _textScale),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              if (_isBannerAdReady && _bannerAd != null)
                SafeArea(
                  top: false,
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
