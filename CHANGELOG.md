# Changelog

All notable changes to this gem are documented here. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Nested savepoints**: outer transaction work was lost on inner `requires_new:`
  rollback. `internal_execute` now marks the current transaction dirty so Rails
  uses `SavepointTransaction` instead of `RestartParentTransaction`.
- **`unique_by: :index_name` lookup**: index names were returned UPPERCASE
  (as Firebird stores them) but Rails 8.1's `InsertAll#find_unique_index_for`
  matches case-sensitively. `indexes` now downcases index names when
  `downcase_columns?` is set.
- **Window functions**: `SELECT *, ROW_NUMBER() OVER (...)` raised
  *"Token unknown, ','"* on Firebird 5. The Arel visitor now expands
  `*, expr` projections into `"TABLE".*, expr`.
- **`preprocess_query` bypass**: `internal_execute` was skipping Rails'
  `preprocess_query`, disabling `ensure_writes_are_allowed`,
  `mark_transaction_written`, and query transformers. Now invoked at the
  top of `internal_execute`.
- **SQL injection in schema introspection** (`table_exists?`, `view_exists?`,
  `indexes`, `column_definitions`, `primary_keys`, `foreign_keys`,
  `sequence_exists?`): names were interpolated raw into `WHERE` clauses.
  All now use `quote()` to escape single quotes.
- **`firebird_version` fallback**: rescue previously set version to
  `25_000` (Firebird 2.5), silently disabling every modern feature. Now
  raises `ActiveRecord::ConnectionNotEstablished` on failure.
- **`auto_incremented?` false positive**: any BIGINT primary key was
  reported as auto-increment. Now requires IDENTITY/GENERATED or a
  sequence-based default.
- **`rename_table` error hiding**: all errors were rewrapped as
  `NotImplementedError`. Now propagates the original error (typically
  `StatementInvalid`).
- **Silent sequence failures**: `create_sequence` / `drop_sequence`
  swallowed every exception and returned `nil`. Now they raise.

### Changed
- Removed duplicated instance-method overrides of `quote_column_name` /
  `quote_table_name` from `Firebird::Quoting`. The class methods on
  `FirebirdAdapter` remain the single source of truth (Rails 8.1 routes
  through `self.class.quote_column_name`).
- Removed dead code: `lib/active_record/extensions.rb` (was never
  loaded, no functional effect) and
  `Firebird::TypeMetadata` subclass (never instantiated — the adapter
  creates `SqlTypeMetadata` directly).
- `downcase_columns?` is no longer advertised as configurable. It must
  return `true` for ActiveRecord's attribute↔column mapping to align
  with Firebird's UPPERCASE identifier folding.

### Added
- `preprocess_query` regression spec (`spec/query_lifecycle_spec.rb`).
- Concurrency, pool, isolation, reconnect and throughput stress tests
  (`spec/stress_spec.rb`).
- Quoting edge cases (`spec/quoting_edge_spec.rb`).
- Exception translation coverage (`spec/exception_edge_spec.rb`).
- Deeply-nested savepoint coverage (`spec/transactions_edge_spec.rb`).

## [8.1.0] - 2026-07-XX

- Initial Rails 8.1 compatibility release. Based on the
  `a377784 Rails 7.2+ compatibility` baseline.
- `quote_column_name` / `quote_table_name` exposed as class methods to
  satisfy `Model.quoted_table_name` (PR #1).
- `internal_execute` rewritten with `materialize_transactions`; added
  transaction and affected-rows tests (PR #2).
- `insert_all` / `upsert_all` via custom `build_insert_sql` (PR #3).

[Unreleased]: https://github.com/rollyar/firebird_adapter/compare/8.1.0...HEAD
[8.1.0]: https://github.com/rollyar/firebird_adapter/releases/tag/8.1.0
