import 'package:supabase_flutter/supabase_flutter.dart';

import 'schema_models.dart';

/// Loads [EditSuggestionSchemaBundle] from Supabase RPC (no table/column names in client).
class EditSuggestionSchemaService {
  EditSuggestionSchemaService(this._client);

  final SupabaseClient _client;

  EditSuggestionSchemaBundle? _cache;
  Future<EditSuggestionSchemaBundle>? _inFlight;

  Future<EditSuggestionSchemaBundle> loadBundle({bool forceRefresh = false}) {
    if (!forceRefresh && _cache != null && _cache!.ok) {
      return Future<EditSuggestionSchemaBundle>.value(_cache!);
    }
    if (!forceRefresh && _inFlight != null) {
      return _inFlight!;
    }
    _inFlight = _fetch();
    return _inFlight!;
  }

  Future<EditSuggestionSchemaBundle> _fetch() async {
    try {
      final dynamic raw =
          await _client.rpc('app_edit_suggestion_schema_bundle');
      final EditSuggestionSchemaBundle b = EditSuggestionSchemaBundle.parse(raw);
      _cache = b;
      return b;
    } catch (_) {
      const EditSuggestionSchemaBundle fail = EditSuggestionSchemaBundle(
        ok: false,
        error: 'rpc_failed',
        reportsSchema: 'public',
        reportsTable: 'reports',
        reportColumns: <SchemaColumn>[],
        targets: <EditSuggestionTarget>[],
      );
      _cache = fail;
      return fail;
    } finally {
      _inFlight = null;
    }
  }

  Future<List<Map<String, String>>> loadFkOptions({
    required String refSchema,
    required String refTable,
    required String pkColumn,
    required String labelColumn,
    String search = '',
    int limit = 40,
  }) async {
    try {
      final dynamic raw = await _client.rpc(
        'app_fk_label_options',
        params: <String, dynamic>{
          'p_ref_schema': refSchema,
          'p_ref_table': refTable,
          'p_pk_column': pkColumn,
          'p_label_column': labelColumn,
          'p_search': search,
          'p_limit': limit,
        },
      );
      if (raw is! List<dynamic>) {
        return const <Map<String, String>>[];
      }
      final List<Map<String, String>> out = <Map<String, String>>[];
      for (final dynamic row in raw) {
        if (row is Map<String, dynamic>) {
          out.add(<String, String>{
            'id': (row['id'] ?? '').toString(),
            'label': (row['label'] ?? '').toString(),
          });
        }
      }
      return out;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }
}
