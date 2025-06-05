defmodule JsonComparator do
  @moduledoc """
  Provides functionality for comparing JSON structures with configurable comparison options.
  """

  @doc """
  Compares two JSON structures for equality with configurable options.

  This function performs a deep comparison of two JSON structures, supporting various data types
  including maps, lists, DateTime objects, and structs. It provides configurable behavior for
  list comparison and DateTime precision.

  ## Parameters

    * `json1` - First JSON structure to compare
    * `json2` - Second JSON structure to compare
    * `opts` - Optional keyword list of comparison options:
      * `:strict_list_order` - When `true`, lists must have identical order to be considered equal.
        Defaults to `false`
      * `:truncate_datetime_microseconds` - When `true`, DateTime comparisons ignore microseconds.
        Defaults to `true`
      * `:error_message` - Custom error message template to use when differences are found.
        The string `%{path}` will be replaced with the path where the difference was found.
        Defaults to "Submitted JSONs do not match: %{path}"

  ## Returns

    * `:ok` - When the structures are equal according to the comparison rules
    * `{:error, message}` - When differences are found, where message is a string indicating
      the path where the first difference was encountered

  ## Examples

      iex> JsonComparator.compare(%{a: 1}, %{a: 1})
      :ok

      iex> JsonComparator.compare(%{a: [1, 2]}, %{a: [2, 1]}, strict_list_order: true)
      {:error, "Submitted JSONs do not match: a[0]"}

      iex> JsonComparator.compare(%{a: 1}, %{a: 2}, error_message: "Values differ at: %{path}")
      {:error, "Values differ at: a"}

      iex> dt1 = DateTime.from_iso8601("2024-01-01T00:00:00.123456Z")
      iex> dt2 = DateTime.from_iso8601("2024-01-01T00:00:00.789012Z")
      iex> JsonComparator.compare(%{time: dt1}, %{time: dt2}, truncate_datetime_microseconds: true)
      :ok
  """
  def compare(json1, json2, opts \\ []) do
    opts =
      Keyword.merge(
        [
          strict_list_order: false,
          truncate_datetime_microseconds: true,
          error_message: "Submitted JSONs do not match: %{path}"
        ],
        opts
      )

    case deep_compare(json1, json2, opts) do
      {:ok, true} ->
        :ok

      {:ok, {false, path}} ->
        {:error, String.replace(opts[:error_message], "%{path}", path)}
    end
  end

  defp deep_compare(%DateTime{} = dt1, %DateTime{} = dt2, opts) do
    if Keyword.get(opts, :truncate_datetime_microseconds, true) do
      # Truncate microseconds for comparison
      dt1_truncated = %{dt1 | microsecond: {0, 0}}
      dt2_truncated = %{dt2 | microsecond: {0, 0}}
      {:ok, DateTime.compare(dt1_truncated, dt2_truncated) == :eq}
    else
      {:ok, DateTime.compare(dt1, dt2) == :eq}
    end
  end

  defp deep_compare(%_{} = struct1, %_{} = struct2, _opts) do
    if struct1.__struct__ == struct2.__struct__ do
      {:ok, struct1 == struct2}
    else
      {:ok, false}
    end
  end

  defp deep_compare(map1, map2, opts) when is_map(map1) and is_map(map2) do
    keys1 = Map.keys(map1)
    keys2 = Map.keys(map2)

    case keys1 -- keys2 do
      [] ->
        Enum.reduce_while(keys1, {:ok, true}, fn key, acc ->
          case deep_compare(map1[key], map2[key], opts) do
            {:ok, true} -> {:cont, acc}
            {:ok, {false, path}} -> {:halt, {:ok, {false, "#{key}.#{path}"}}}
            {:ok, false} -> {:halt, {:ok, {false, key}}}
          end
        end)

      _missing ->
        {:ok, {false, Enum.at(keys1 -- keys2, 0)}}
    end
  end

  defp deep_compare(list1, list2, opts) when is_list(list1) and is_list(list2) do
    cond do
      length(list1) > length(list2) ->
        {:ok, {false, "[#{length(list2)}]"}}

      length(list1) < length(list2) ->
        {:ok, {false, "[#{length(list1)}]"}}

      Keyword.get(opts, :strict_list_order, false) ->
        # Strict order comparison
        list1
        |> Enum.zip(list2)
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, true}, fn {{item1, item2}, index}, acc ->
          case deep_compare(item1, item2, opts) do
            {:ok, true} -> {:cont, acc}
            {:ok, {false, path}} -> {:halt, {:ok, {false, "[#{index}].#{path}"}}}
            {:ok, false} -> {:halt, {:ok, {false, "[#{index}]"}}}
          end
        end)

      true ->
        # Compare lists ignoring order
        list2_remaining =
          Enum.reduce_while(list1, list2, fn item1, acc ->
            case Enum.find_index(acc, &match?({:ok, true}, deep_compare(&1, item1, opts))) do
              nil -> {:halt, nil}
              idx -> {:cont, List.delete_at(acc, idx)}
            end
          end)

        {:ok, list2_remaining == []}
    end
  end

  defp deep_compare(val1, val2, _opts) when is_number(val1) and is_number(val2) do
    {:ok, val1 == val2}
  end

  defp deep_compare(val1, val2, _opts) do
    {:ok, val1 === val2}
  end
end
