#!/usr/bin/env python3
"""Fill multi-Strong morphology arrays from direct STEPBible TAGNT data.

This script keeps the KJV-facing word grouping, but replaces missing morphology
slots with exact per-code morphology when the verse and Strong's sequence align
with KJV/TR-compatible Greek TAGNT tokens.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter, defaultdict


INPUT_FILE = 'assets/kjv_strongs.json'
OUTPUT_FILE = 'assets/kjv_strongs.json'
TAGNT_BASE = (
    'https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master/'
    'Translators%20Amalgamated%20OT%2BNT/'
)

TAGNT_FILES = (
    'TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt',
    'TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt',
)

BOOK_ABBREVIATIONS = {
    'Matthew': 'Mat',
    'Mark': 'Mrk',
    'Luke': 'Luk',
    'John': 'Jhn',
    'Acts': 'Act',
    'Romans': 'Rom',
    '1 Corinthians': '1Co',
    '2 Corinthians': '2Co',
    'Galatians': 'Gal',
    'Ephesians': 'Eph',
    'Philippians': 'Php',
    'Colossians': 'Col',
    '1 Thessalonians': '1Th',
    '2 Thessalonians': '2Th',
    '1 Timothy': '1Ti',
    '2 Timothy': '2Ti',
    'Titus': 'Tit',
    'Philemon': 'Phm',
    'Hebrews': 'Heb',
    'James': 'Jas',
    '1 Peter': '1Pe',
    '2 Peter': '2Pe',
    '1 John': '1Jn',
    '2 John': '2Jn',
    '3 John': '3Jn',
    'Jude': 'Jud',
    'Revelation': 'Rev',
}

VERSE_RE = re.compile(r'^([1-3]?[A-Za-z]{3})\.(\d+)\.(\d+)$')
CODE_RE = re.compile(r'([GH])(\d+)')
TAGNT_WORD_RE = re.compile(r'^([1-3]?[A-Za-z]{3})\.(\d+)\.(\d+)#\d+=([^\t]+)$')


def normalize_code(code: str) -> str:
    code = code.strip().strip('{}')
    match = CODE_RE.search(code)
    if not match:
        return code.strip()
    prefix, digits = match.groups()
    return f'{prefix}{int(digits)}'


def normalize_codes(raw_codes: str) -> list[str]:
    return [normalize_code(part) for part in raw_codes.split(';') if part.strip()]


def parse_marker(raw_marker: str) -> set[str]:
    return {ch for ch in raw_marker if ch in 'NKO'}


def fetch_tagnt_file(file_name: str) -> str:
    url = TAGNT_BASE + urllib.parse.quote(file_name, safe='')
    with urllib.request.urlopen(url) as response:
        return response.read().decode('utf-8')


def build_step_index(text: str) -> dict[tuple[str, int, int], list[dict[str, object]]]:
    index: dict[tuple[str, int, int], list[dict[str, object]]] = defaultdict(list)

    for raw_line in text.splitlines():
        line = raw_line.rstrip('\n')
        if not line or line.startswith('#') or line.startswith('Word & Type'):
            continue

        parts = line.split('\t')
        if len(parts) < 4:
            continue

        word_match = TAGNT_WORD_RE.match(parts[0])
        if not word_match:
            continue

        abbrev, chapter, verse, marker = word_match.groups()
        if '=' not in parts[3]:
            continue

        strongs_code, grammar = parts[3].split('=', 1)
        normalized_code = normalize_code(strongs_code)
        if not normalized_code or not grammar:
            continue

        index[(abbrev, int(chapter), int(verse))].append({
            'code': normalized_code,
            'grammar': grammar.strip(),
            'k_safe': 'K' in parse_marker(marker),
        })

    return index


def subsequence_positions(target: tuple[str, ...], source: list[str]) -> list[int] | None:
    positions: list[int] = []
    start = 0
    for code in target:
        try:
            idx = source.index(code, start)
        except ValueError:
            return None
        positions.append(idx)
        start = idx + 1
    return positions


def reorder_match_morph(
    target: tuple[str, ...],
    row_codes: list[str],
    row_grammar: list[str],
) -> list[str] | None:
    if len(target) != len(row_codes):
        return None
    if len(set(target)) != len(target):
        return None
    if Counter(target) != Counter(row_codes):
        return None

    grammar_by_code = dict(zip(row_codes, row_grammar))
    return [grammar_by_code[code] for code in target]


def to_morph_list(word: dict) -> list[str | None]:
    morph = word.get('m')
    if morph is None:
        return []
    if isinstance(morph, list):
        return list(morph)
    if isinstance(morph, str):
        if len(word.get('s', [])) > 1:
            return [morph] + [None] * (len(word['s']) - 1)
        return [morph]
    return []


def count_remaining_null_slots(data: dict) -> int:
    total = 0
    for verse in data.get('verses', []):
        for word in verse.get('words', []):
            morph = word.get('m')
            if isinstance(morph, list):
                total += sum(item is None for item in morph)
    return total


def enrich_data(data: dict) -> tuple[dict, int, int, int]:
    replaced_words = 0
    filled_slots = 0
    matched_sequences = 0

    index: dict[tuple[str, int, int], list[dict[str, object]]] = defaultdict(list)

    for file_name in TAGNT_FILES:
        print(f'Fetching {file_name}...')
        text = fetch_tagnt_file(file_name)
        file_index = build_step_index(text)
        for verse_key, rows in file_index.items():
            index[verse_key].extend(rows)

    for verse in data.get('verses', []):
        book_name = verse['book']
        book_abbrev = BOOK_ABBREVIATIONS.get(book_name)
        if book_abbrev is None:
            continue

        verse_key = (book_abbrev, verse['chapter'], verse['verse'])
        verse_rows = index.get(verse_key)
        if not verse_rows:
            continue

        k_safe_rows = [row for row in verse_rows if row['k_safe']]
        if not k_safe_rows:
            continue

        row_cursor = 0

        for word in verse.get('words', []):
            strongs = tuple(normalize_code(code) for code in word.get('s', []))
            if len(strongs) <= 1:
                continue

            current_morph = to_morph_list(word)
            if current_morph and all(item is not None for item in current_morph):
                continue

            matched_positions: list[int] | None = None
            step_morph: list[str] | None = None

            for idx in range(row_cursor, len(k_safe_rows) - len(strongs) + 1):
                window = k_safe_rows[idx:idx + len(strongs)]
                window_codes = tuple(row['code'] for row in window)
                if window_codes == strongs:
                    matched_positions = list(range(idx, idx + len(strongs)))
                    step_morph = [row['grammar'] for row in window]
                    break

            if step_morph is None:
                positions = subsequence_positions(
                    strongs,
                    [row['code'] for row in k_safe_rows[row_cursor:]],
                )
                if positions is not None:
                    matched_positions = [row_cursor + position for position in positions]
                    step_morph = [k_safe_rows[position]['grammar'] for position in matched_positions]

            if step_morph is None:
                for idx in range(row_cursor, len(k_safe_rows) - len(strongs) + 1):
                    window = k_safe_rows[idx:idx + len(strongs)]
                    reordered = reorder_match_morph(
                        strongs,
                        [row['code'] for row in window],
                        [row['grammar'] for row in window],
                    )
                    if reordered is None:
                        continue
                    matched_positions = list(range(idx, idx + len(strongs)))
                    step_morph = reordered
                    break

            if step_morph is None or matched_positions is None:
                continue

            row_cursor = matched_positions[-1] + 1

            morph_list = current_morph
            if morph_list == step_morph:
                matched_sequences += 1
                continue

            old_slots = sum(item is None for item in morph_list)
            new_slots = sum(item is None for item in step_morph)

            word['m'] = step_morph
            replaced_words += 1
            matched_sequences += 1
            filled_slots += max(0, old_slots - new_slots)

    metadata = data.setdefault('metadata', {})
    metadata['morph_enrichment_source'] = (
        'STEPBible TAGNT direct Greek NT, exact verse and Strong\'s-token '
        'alignment, restricted to rows with explicit uppercase K markers '
        '(KJV/TR-compatible)'
    )
    metadata['morph_enrichment_license'] = 'CC BY 4.0 via STEPBible.org'

    return data, matched_sequences, replaced_words, filled_slots


def main() -> None:
    print(f'Loading {INPUT_FILE}...')
    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as handle:
            data = json.load(handle)
    except Exception as exc:
        print(f'Error loading JSON: {exc}')
        sys.exit(1)

    before_nulls = count_remaining_null_slots(data)
    print(f'Null morphology slots before: {before_nulls}')

    try:
        data, matched_sequences, replaced_words, filled_slots = enrich_data(data)
    except Exception as exc:
        print(f'Error enriching morphology: {exc}')
        sys.exit(1)

    after_nulls = count_remaining_null_slots(data)

    print(f'Exact STEP sequence matches: {matched_sequences}')
    print(f'Words updated from STEP data: {replaced_words}')
    print(f'Null slots filled: {filled_slots}')
    print(f'Null morphology slots after: {after_nulls}')

    print(f'Writing {OUTPUT_FILE}...')
    try:
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
    except Exception as exc:
        print(f'Error saving JSON: {exc}')
        sys.exit(1)

    print('Sample enriched entries:')
    shown = 0
    for verse in data.get('verses', []):
        for word in verse.get('words', []):
            morph = word.get('m')
            if len(word.get('s', [])) > 1 and isinstance(morph, list) and all(morph):
                print(
                    f"  {verse['book']} {verse['chapter']}:{verse['verse']} | "
                    f"{word['w']} | {word['s']} | {morph}",
                )
                shown += 1
                if shown >= 5:
                    return


if __name__ == '__main__':
    main()
