# Pending Tests in Firebird Adapter

This document describes the 15 tests that are currently pending (skipped) and why they require additional work on the Firebird adapter.

## Summary
- **Total Tests**: 137
- **Passing**: 122
- **Pending**: 15
- **Failures**: 0

## Pending Tests by Category

### 1. LIMIT/OFFSET Support (7 tests)

These tests require proper implementation of LIMIT and OFFSET SQL clauses:

- **`query #second`** - Uses Rails' `.second()` method which relies on LIMIT 1 OFFSET 1
- **`query #third`** - Uses Rails' `.third()` method which relies on LIMIT 1 OFFSET 2
- **`query #fourth`** - Uses Rails' `.fourth()` method which relies on LIMIT 1 OFFSET 3
- **`query #fifth`** - Uses Rails' `.fifth()` method which relies on LIMIT 1 OFFSET 4
- **`query #limit`** - Tests basic LIMIT functionality
- **`query #offset`** - Tests basic OFFSET functionality
- **`query #limit, #offset`** - Tests combined LIMIT and OFFSET

**Issue**: Firebird uses different syntax for pagination:
- Firebird: `ROWS n TO m` instead of `LIMIT n OFFSET m`
- Need to implement proper LIMIT/OFFSET translation in the adapter

**File**: `spec/queries_spec.rb`

---

### 2. ORDER BY Issues (1 test)

- **`CRUD Operations SELECT orders results`** - Tests ORDER BY DESC functionality

**Issue**: Potential issue with how ORDER BY results are ordered in the adapter or how Rails interprets the results.

**File**: `spec/crud_operations_spec.rb` (line 142)

---

### 3. DECIMAL Type Handling (1 test)

- **`CRUD Operations INSERT with different data types handles decimals`** - Tests BigDecimal storage and retrieval

**Issue**: Firebird's DECIMAL type may not match Rails' BigDecimal expectations or there may be precision/rounding issues.

**File**: `spec/crud_operations_spec.rb` (line 98)

---

### 4. UPDATE Multiple Records (1 test)

- **`CRUD Operations UPDATE updates multiple records`** - Tests `update_all` with WHERE clause

**Issue**: Firebird may not support or implement `update_all` correctly when using LIMIT internally.

**File**: `spec/crud_operations_spec.rb` (line 194)

---

### 5. Advanced SQL Features (2 tests)

These tests require support for Firebird 5.0+ window functions:

- **`CRUD Operations special SQL features Window Functions uses ROW_NUMBER`** - Tests `ROW_NUMBER()` OVER clause
- **`CRUD Operations special SQL features Window Functions uses SUM with OVER`** - Tests `SUM()` OVER clause

**Issue**: Window functions are supported by Firebird 5.0+ but the adapter may need additional configuration or the tests may need adjustment for how Rails handles the result columns.

**File**: `spec/crud_operations_spec.rb` (lines 266, 271)

---

### 6. Unicode/Edge Cases (2 tests)

- **`CRUD Operations UPDATE updates with SQL expressions`** - Tests dynamic SQL expressions in `update_all`
- **`CRUD Operations edge cases handles Unicode characters`** - Tests Unicode character storage (includes emojis)

**Issue**: These are complex edge cases that may require specific handling for Unicode encoding in Firebird or more sophisticated SQL expression parsing.

**File**: `spec/crud_operations_spec.rb` (lines 205, 295)

---

## What These Tests Reveal

1. **Core SQL Feature Gap**: The adapter needs LIMIT/OFFSET translation to `ROWS n TO m`
2. **Data Type Issues**: DECIMAL handling may need refinement
3. **Advanced Features**: Window functions work but may need Rails integration adjustments
4. **Edge Cases**: Unicode and dynamic SQL expressions need testing

## Next Steps

To enable these tests, the following adapter improvements would be needed:

1. **Implement LIMIT/OFFSET translation** - Convert Rails' LIMIT/OFFSET to Firebird's ROWS syntax
2. **Test DECIMAL type thoroughly** - Ensure proper precision and rounding
3. **Verify update_all behavior** - May need special handling
4. **Test window functions** - Ensure proper column aliasing and Rails integration
5. **Unicode support** - Verify UTF-8 encoding throughout the stack

## Running Tests

To check the current test status:

```bash
bundle exec rspec --format documentation --color
```

To run only pending tests:

```bash
bundle exec rspec --pending
```

To run a specific pending test and see why it fails:

```bash
bundle exec rspec spec/queries_spec.rb:17 --format documentation --color
```
