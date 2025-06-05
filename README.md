# JsonComparator

[![Hex.pm](https://img.shields.io/hexpm/v/json_comparator.svg)](https://hex.pm/packages/json_comparator)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/json_comparator)

A robust Elixir library for deep comparison of JSON-like structures with configurable comparison options.

## Features

- Deep comparison of nested structures
- Flexible list comparison (ordered or unordered)
- DateTime comparison with configurable precision
- Struct comparison support
- Custom error messages
- Detailed path reporting for differences

## Installation

Add `json_comparator` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:json_comparator, "~> 1.0.0"}
  ]
end
```

Then run:

```bash
$ mix deps.get
```

## Configuration Options

The compare function accepts the following options:

- `strict_list_order` (boolean, default: false) - When true, lists must have identical ordering
- `truncate_datetime_microseconds` (boolean, default: true) - When true, ignores microseconds in DateTime comparisons
- `error_message` (string, default: "Submitted JSONs do not match: %{path}") - Custom error message template
- `deep_compare` (boolean, default: false) - When true, collects all differences instead of stopping at the first one

## Usage Examples

### Basic comparison

```elixir
iex> JsonComparator.compare(%{a: 1, b: 2}, %{a: 1, b: 2})
:ok

iex> JsonComparator.compare(%{a: 1, b: 2}, %{a: 1, b: 3})
{:error, "Submitted JSONs do not match: b"}
```

Unordered list comparison (default behavior):

```elixir
iex> JsonComparator.compare([1, 2, 3], [3, 2, 1])
:ok
```

Ordered list comparison:

```elixir
iex> JsonComparator.compare([1, 2, 3], [1, 2, 3], strict_list_order: true)
:ok

iex> JsonComparator.compare([1, 2, 3], [3, 2, 1], strict_list_order: true)
{:error, "Submitted JSONs do not match: [0]"}
```

DateTime comparison:

```elixir
iex> dt1 = DateTime.from_naive!(~N[2024-01-01 00:00:00.123456], "Etc/UTC")
iex> dt2 = DateTime.from_naive!(~N[2024-01-01 00:00:00.789012], "Etc/UTC")

# By default microseconds are truncated
iex> JsonComparator.compare(dt1, dt2)
:ok

# Comparing with exact microseconds
iex> JsonComparator.compare(dt1, dt2, truncate_datetime_microseconds: false)
{:error, "Submitted JSONs do not match: "}
```

Custom error messages:

```elixir
iex> JsonComparator.compare(%{a: 1}, %{a: 2}, error_message: "Values differ at: %{path}")
{:error, "Values differ at: a"}
```

Complex nested structures:

```elixir
iex> complex1 = %{
...>   user: %{
...>     name: "Alice",
...>     roles: ["admin", "editor"],
...>     metadata: %{joined_at: DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC")}
...>   }
...> }

iex> complex2 = %{
...>   user: %{
...>     name: "Alice",
...>     roles: ["editor", "admin"],
...>     metadata: %{joined_at: DateTime.from_naive!(~N[2024-01-01 00:00:00.500000], "Etc/UTC")}
...>   }
...> }

iex> JsonComparator.compare(complex1, complex2)
:ok
```

### Collecting all differences

If you need to find all differences between structures rather than just the first one, use the `deep_compare: true` option or the convenience function `compare_all/3`:

```elixir
iex> map1 = %{a: 1, b: 2, c: 3, d: %{e: 4, f: 5}}
iex> map2 = %{a: 1, b: 7, d: %{e: 9, g: 8}, h: 10}

# Using deep_compare option
iex> {:error, differences} = JsonComparator.compare(map1, map2, deep_compare: true)

# Or using the convenience function (equivalent)
iex> {:error, differences} = JsonComparator.compare_all(map1, map2)

iex> differences
[
  {"b", %{expected: 2, actual: 7, type: :value_mismatch}},
  {"c", %{expected: 3, actual: nil, type: :missing_key}},
  {"d.e", %{expected: 4, actual: 9, type: :value_mismatch}},
  {"d.f", %{expected: 5, actual: nil, type: :missing_key}},
  {"d.g", %{expected: nil, actual: 8, type: :extra_key}},
  {"h", %{expected: nil, actual: 10, type: :extra_key}}
]

# Process all differences
iex> Enum.each(differences, fn {path, details} ->
...>   IO.puts("Difference at #{path}: expected #{inspect(details.expected)}, got #{inspect(details.actual)}")
...> end)
Difference at b: expected 2, got 7
Difference at c: expected 3, got nil
Difference at d.e: expected 4, got 9
Difference at d.f: expected 5, got nil
Difference at d.g: expected nil, got 8
Difference at h: expected nil, got 10
```

The returned differences include detailed information about each discrepancy, including the exact path, expected and actual values, and the type of difference.
