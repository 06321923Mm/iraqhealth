import 'arabic_search_normalize.dart';

/// نوع السطر في قائمة الاقتراحات.
enum SearchSuggestionKind { doctorName, specialization, area }

class SearchSuggestionRow {
  const SearchSuggestionRow({
    required this.label,
    required this.kind,
  });

  final String label;
  final SearchSuggestionKind kind;
}

/// اقتراحات من بيانات الأطباء المحمّلة من Supabase (نفس الدفعات المعروضة في الرئيسية).
List<SearchSuggestionRow> computeLocalSearchSuggestions({
  required String query,
  required List<String> doctorNames,
  required List<String> areas,
  required List<String> specializations,
  int limit = 12,
}) {
  final String q = query.trim();
  if (q.isEmpty) {
    return <SearchSuggestionRow>[];
  }
  final String nq = normalizeArabic(q);
  if (nq.isEmpty) {
    return <SearchSuggestionRow>[];
  }

  bool matches(String raw) {
    final String x = normalizeArabic(raw);
    return x.contains(nq);
  }

  bool starts(String raw) {
    final String x = normalizeArabic(raw);
    return x.startsWith(nq);
  }

  final List<({String label, SearchSuggestionKind kind, int rank})> acc =
      <({String label, SearchSuggestionKind kind, int rank})>[];

  void addUnique(String label, SearchSuggestionKind kind, int rank) {
    if (label.trim().isEmpty) {
      return;
    }
    if (acc.any((({String label, SearchSuggestionKind kind, int rank}) e) =>
        e.label == label && e.kind == kind)) {
      return;
    }
    acc.add((label: label, kind: kind, rank: rank));
  }

  for (final String name in doctorNames) {
    if (matches(name)) {
      addUnique(
        name,
        SearchSuggestionKind.doctorName,
        starts(name) ? 0 : 3,
      );
    }
  }

  for (final String s in specializations) {
    if (matches(s)) {
      addUnique(s, SearchSuggestionKind.specialization, starts(s) ? 1 : 4);
    }
  }

  for (final String a in areas) {
    if (matches(a)) {
      addUnique(a, SearchSuggestionKind.area, starts(a) ? 2 : 5);
    }
  }

  acc.sort(
    (
      ({String label, SearchSuggestionKind kind, int rank}) a,
      ({String label, SearchSuggestionKind kind, int rank}) b,
    ) {
      final int byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) {
        return byRank;
      }
      return a.label.compareTo(b.label);
    },
  );

  final List<SearchSuggestionRow> out = <SearchSuggestionRow>[];
  for (final ({String label, SearchSuggestionKind kind, int rank}) e in acc) {
    out.add(SearchSuggestionRow(label: e.label, kind: e.kind));
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}
