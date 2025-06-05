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

## Usage Examples

Basic comparison:

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
