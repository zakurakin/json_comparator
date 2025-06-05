defmodule JsonComparator do
  @moduledoc """
  Provides functionality for comparing JSON structures with configurable comparison options.
  """

  @doc """
  Compares two JSON structures for equality with configurable options.

  This function performs a deep comparison of two JSON structures, supporting various data types
  including maps, lists, DateTime objects, and structs. It provides configurable behavior for
  list comparison and DateTime precision.

  By default, this function stops and returns on the first difference found.
  Use the `deep_compare: true` option to collect all differences.

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
      * `:deep_compare` - When `true`, collects all differences instead of stopping at the first one.
        Defaults to `false`. When `true`, returns `{:error, differences}` where `differences` is a list
        of `{path, details}` tuples.

  ## Returns

    * `:ok` - When the structures are equal according to the comparison rules
    * `{:error, message}` - When differences are found and `deep_compare: false`, where message is a
       string indicating the path where the first difference was encountered
    * `{:error, differences}` - When differences are found and `deep_compare: true`, where differences
       is a list of tuples containing path and details about each difference
  """
  def compare(json1, json2, opts \\ []) do
    opts =
      [
        strict_list_order: Keyword.get(opts, :strict_list_order, false),
        truncate_datetime_microseconds: Keyword.get(opts, :truncate_datetime_microseconds, true),
        error_message: Keyword.get(opts, :error_message, "Submitted JSONs do not match: %{path}"),
        deep_compare: Keyword.get(opts, :deep_compare, false)
      ]

    if opts[:deep_compare] do
      # Collect all differences
      {diffs, _} = collect_all_differences(json1, json2, "", opts)

      if diffs == [] do
        :ok
      else
        {:error, diffs}
      end
    else
      # Stop at first difference (original behavior)
      case deep_compare(json1, json2, opts) do
        {:ok, true} ->
          :ok

        {:ok, false} ->
          {:error, String.replace(opts[:error_message], "%{path}", "")}

        {:ok, {false, path}} ->
          path_str = to_string(path)
          {:error, String.replace(opts[:error_message], "%{path}", path_str)}
      end
    end
  end

  # Collects all differences between two JSON structures
  defp collect_all_differences(%DateTime{} = dt1, %DateTime{} = dt2, path, opts) do
    if Keyword.get(opts, :truncate_datetime_microseconds, true) do
      dt1_truncated = %{dt1 | microsecond: {0, 0}}
      dt2_truncated = %{dt2 | microsecond: {0, 0}}

      if DateTime.compare(dt1_truncated, dt2_truncated) == :eq do
        {[], true}
      else
        {[
           {path,
            %{
              expected: dt1,
              actual: dt2,
              type: :datetime_mismatch
            }}
         ], false}
      end
    else
      if DateTime.compare(dt1, dt2) == :eq do
        {[], true}
      else
        {[
           {path,
            %{
              expected: dt1,
              actual: dt2,
              type: :datetime_mismatch
            }}
         ], false}
      end
    end
  end

  defp collect_all_differences(%_{} = struct1, %_{} = struct2, path, opts) do
    if struct1.__struct__ != struct2.__struct__ do
      {[
         {path,
          %{
            expected: struct1.__struct__,
            actual: struct2.__struct__,
            type: :struct_type_mismatch
          }}
       ], false}
    else
      # Compare struct fields as maps
      map1 = Map.from_struct(struct1)
      map2 = Map.from_struct(struct2)
      collect_all_differences(map1, map2, path, opts)
    end
  end

  defp collect_all_differences(%_{} = struct1, _non_struct, path, _opts) do
    {[
       {path,
        %{
          expected: struct1.__struct__,
          actual: "not a struct",
          type: :type_mismatch
        }}
     ], false}
  end

  defp collect_all_differences(_non_struct, %_{} = struct2, path, _opts) do
    {[
       {path,
        %{
          expected: "not a struct",
          actual: struct2.__struct__,
          type: :type_mismatch
        }}
     ], false}
  end

  defp collect_all_differences(map1, map2, path, opts) when is_map(map1) and is_map(map2) do
    keys1 = Map.keys(map1)
    keys2 = Map.keys(map2)

    # Check for missing keys in map2
    missing_diffs =
      keys1
      |> Enum.filter(fn k -> not Map.has_key?(map2, k) end)
      |> Enum.map(fn k ->
        path_key = if path == "", do: "#{k}", else: "#{path}.#{k}"

        {path_key,
         %{
           expected: map1[k],
           actual: nil,
           type: :missing_key
         }}
      end)

    # Check for extra keys in map2
    extra_diffs =
      keys2
      |> Enum.filter(fn k -> not Map.has_key?(map1, k) end)
      |> Enum.map(fn k ->
        path_key = if path == "", do: "#{k}", else: "#{path}.#{k}"

        {path_key,
         %{
           expected: nil,
           actual: map2[k],
           type: :extra_key
         }}
      end)

    # Check for value differences in common keys
    common_keys = keys1 |> MapSet.new() |> MapSet.intersection(MapSet.new(keys2)) |> MapSet.to_list()

    value_diffs =
      Enum.reduce(common_keys, [], fn key, acc ->
        path_key = if path == "", do: "#{key}", else: "#{path}.#{key}"
        {diffs, _} = collect_all_differences(map1[key], map2[key], path_key, opts)
        acc ++ diffs
      end)

    {missing_diffs ++ extra_diffs ++ value_diffs, missing_diffs == [] and extra_diffs == [] and value_diffs == []}
  end

  defp collect_all_differences(list1, list2, path, opts) when is_list(list1) and is_list(list2) do
    if length(list1) != length(list2) do
      {[
         {path,
          %{
            expected: length(list1),
            actual: length(list2),
            type: :list_length_mismatch
          }}
       ], false}
    else
      if Keyword.get(opts, :strict_list_order, false) do
        collect_all_differences_lists_strict(list1, list2, path, opts)
      else
        collect_all_differences_lists_unordered(list1, list2, path, opts)
      end
    end
  end

  defp collect_all_differences(list1, non_list, path, _opts) when is_list(list1) do
    {[
       {path,
        %{
          expected: "list",
          actual: "#{inspect(non_list)}",
          type: :type_mismatch
        }}
     ], false}
  end

  defp collect_all_differences(non_list, list2, path, _opts) when is_list(list2) do
    {[
       {path,
        %{
          expected: "#{inspect(non_list)}",
          actual: "list",
          type: :type_mismatch
        }}
     ], false}
  end

  defp collect_all_differences(val1, val2, path, _opts) do
    if val1 === val2 do
      {[], true}
    else
      {[
         {path,
          %{
            expected: val1,
            actual: val2,
            type: :value_mismatch
          }}
       ], false}
    end
  end

  defp collect_all_differences_lists_strict(list1, list2, path, opts) do
    list1
    |> Enum.zip(list2)
    |> Enum.with_index()
    |> Enum.reduce({[], true}, fn {{item1, item2}, index}, {diffs, all_equal} ->
      path_idx = "#{path}[#{index}]"
      {item_diffs, items_equal} = collect_all_differences(item1, item2, path_idx, opts)
      {diffs ++ item_diffs, all_equal and items_equal}
    end)
  end

  defp collect_all_differences_lists_unordered(list1, list2, path, opts) do
    # This is a greedy matching algorithm that may not find all optimal matches
    # but it's sufficient for most practical cases
    {remaining_items, matched_pairs, unmatched} =
      Enum.reduce(list1, {list2, [], []}, fn item1, {remaining, matched, unmatched} ->
        case find_matching_item(item1, remaining, opts) do
          {:ok, item2, new_remaining} ->
            {new_remaining, [{item1, item2} | matched], unmatched}

          :error ->
            {remaining, matched, [item1 | unmatched]}
        end
      end)

    # Process matched pairs to find internal differences
    matched_diffs =
      matched_pairs
      |> Enum.with_index()
      |> Enum.reduce([], fn {{item1, item2}, index}, acc ->
        path_idx = "#{path}[#{index}]"
        {diffs, _} = collect_all_differences(item1, item2, path_idx, opts)
        acc ++ diffs
      end)

    # Handle unmatched items from both lists
    unmatched_diffs1 =
      unmatched
      |> Enum.with_index(length(matched_pairs))
      |> Enum.map(fn {item, index} ->
        path_idx = "#{path}[#{index}]"

        {path_idx,
         %{
           expected: item,
           actual: nil,
           type: :unmatched_list_item
         }}
      end)

    unmatched_diffs2 =
      remaining_items
      |> Enum.with_index(length(matched_pairs) + length(unmatched))
      |> Enum.map(fn {item, index} ->
        path_idx = "#{path}[#{index}]"

        {path_idx,
         %{
           expected: nil,
           actual: item,
           type: :unmatched_list_item
         }}
      end)

    all_diffs = matched_diffs ++ unmatched_diffs1 ++ unmatched_diffs2
    {all_diffs, all_diffs == []}
  end

  defp find_matching_item(item, list, opts) do
    Enum.reduce_while(Enum.with_index(list), :error, fn {candidate, idx}, _acc ->
      {_diffs, is_match} = collect_all_differences(item, candidate, "", opts)

      if is_match do
        # Remove the matched item from the list
        new_list = List.delete_at(list, idx)
        {:halt, {:ok, candidate, new_list}}
      else
        {:cont, :error}
      end
    end)
  end

  defp deep_compare(%DateTime{} = dt1, %DateTime{} = dt2, opts) do
    compare_result =
      if Keyword.get(opts, :truncate_datetime_microseconds, true) do
        dt1_truncated = %{dt1 | microsecond: {0, 0}}
        dt2_truncated = %{dt2 | microsecond: {0, 0}}
        DateTime.compare(dt1_truncated, dt2_truncated) == :eq
      else
        DateTime.compare(dt1, dt2) == :eq
      end

    {:ok, compare_result}
  end

  defp deep_compare(%_{} = struct1, %_{} = struct2, _opts) do
    {:ok, struct1.__struct__ == struct2.__struct__ and struct1 == struct2}
  end

  defp deep_compare(map1, map2, opts) when is_map(map1) and is_map(map2) do
    compare_map_keys(Map.keys(map1), Map.keys(map2), map1, map2, opts)
  end

  defp deep_compare(list1, list2, opts) when is_list(list1) and is_list(list2) do
    compare_lists(list1, list2, opts)
  end

  defp deep_compare(val1, val2, _opts) do
    {:ok, val1 === val2}
  end

  defp compare_map_keys(keys1, keys2, map1, map2, opts) do
    case keys1 -- keys2 do
      [] ->
        case keys2 -- keys1 do
          [] -> compare_map_values(keys1, map1, map2, opts)
          [missing_key | _] -> {:ok, {false, missing_key}}
        end

      [missing_key | _] ->
        {:ok, {false, missing_key}}
    end
  end

  defp compare_map_values(keys, map1, map2, opts) do
    Enum.reduce_while(keys, {:ok, true}, fn key, acc ->
      case deep_compare(map1[key], map2[key], opts) do
        {:ok, true} -> {:cont, acc}
        {:ok, {false, path}} -> {:halt, {:ok, {false, "#{key}.#{path}"}}}
        {:ok, false} -> {:halt, {:ok, {false, key}}}
      end
    end)
  end

  defp compare_lists(list1, list2, opts) do
    cond do
      length(list1) != length(list2) ->
        {:ok, {false, "[#{min(length(list1), length(list2))}]"}}

      Keyword.get(opts, :strict_list_order, false) ->
        compare_lists_strict(list1, list2, opts)

      true ->
        compare_lists_unordered(list1, list2, opts)
    end
  end

  defp compare_lists_strict(list1, list2, opts) do
    list1
    |> Enum.zip(list2)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, true}, fn {{item1, item2}, index}, acc ->
      case deep_compare(item1, item2, opts) do
        {:ok, true} -> {:cont, acc}
        {:ok, {false, path}} -> {:halt, {:ok, {false, "[#{index}]#{path}"}}}
        {:ok, false} -> {:halt, {:ok, {false, "[#{index}]"}}}
      end
    end)
  end

  defp compare_lists_unordered(list1, list2, opts) do
    result =
      Enum.reduce_while(list1, list2, fn item1, acc ->
        case Enum.find_index(acc, &match?({:ok, true}, deep_compare(&1, item1, opts))) do
          nil -> {:halt, nil}
          idx -> {:cont, List.delete_at(acc, idx)}
        end
      end)

    {:ok, result == []}
  end
end
