class Word {
  final String w;
  final List<String> s;
  final List<String?> m;
  final bool a;
  final String? p;

  const Word({
    required this.w,
    required this.s,
    this.m = const [],
    this.a = false,
    this.p,
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    final morphJson = json['m'];
    List<String?> morphList = [];

    if (morphJson != null) {
      if (morphJson is String) {
        // Legacy format: single string
        morphList = [morphJson];
      } else if (morphJson is List) {
        // New format: array of strings/nulls
        morphList = (morphJson).map((m) => m as String?).toList();
      }
    }

    return Word(
      w: json['w'] as String,
      s: (json['s'] as List<dynamic>?)?.cast<String>() ?? [],
      m: morphList,
      a: json['a'] as bool? ?? false,
      p: json['p'] as String?,
    );
  }
}

class Verse {
  final String bookName;
  final int bookNum;
  final int chapter;
  final int verse;
  final List<Word> words;

  Verse({
    required this.bookName,
    required this.bookNum,
    required this.chapter,
    required this.verse,
    required this.words,
  });

  factory Verse.fromJson(Map<String, dynamic> json) {
    return Verse(
      bookName: json['book'] as String,
      bookNum: json['book_num'] as int,
      chapter: json['chapter'] as int,
      verse: json['verse'] as int,
      words: (json['words'] as List<dynamic>)
          .map((w) => Word.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }

  String get plainText {
    final buffer = StringBuffer();
    for (final word in words) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word.w);
      if (word.p != null) buffer.write(word.p);
    }
    return buffer.toString();
  }

  String get reference => '$bookName $chapter:$verse';
}
