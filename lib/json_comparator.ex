defmodule JsonComparator do
  @moduledoc """

    Provides functionality for comparing JSON structures with configurable comparison options.

    JsonComparator enables deep comparison of complex data structures like those returned from
    JSON parsing, with support for nested maps, lists, DateTime objects, and structs.

    ## Key Features

    * Deep comparison of nested structures
    * Flexible list comparison (ordered or unordered)
    * DateTime comparison with configurable precision
    * Struct comparison support
    * Custom error messages
    * Detailed path reporting for differences
    * Comprehensive difference collection with `deep_compare` option

    ## Usage

    Basic comparison (returns `:ok` or a single error):

        JsonComparator.compare(json1, json2, options)

    Collect all differences between structures:

        JsonComparator.compare(json1, json2, deep_compare: true)

    See `compare/3` for more details and examples.
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

  ## Examples

      # Basic comparison (stops at first difference)
      iex> JsonComparator.compare(%{a: 1, b: 2}, %{a: 1, b: 2})
      :ok

      iex> JsonComparator.compare(%{a: 1, b: 2}, %{a: 1, b: 3})
      {:error, "Submitted JSONs do not match: b"}

      # Unordered list comparison (default behavior)
      iex> JsonComparator.compare([1, 2, 3], [3, 2, 1])
      :ok

      # Ordered list comparison
      iex> JsonComparator.compare([1, 2, 3], [1, 2, 3], strict_list_order: true)
      :ok

      # Custom error message
      iex> JsonComparator.compare(%{a: 1}, %{a: 2}, error_message: "Values differ at: %{path}")
      {:error, "Values differ at: a"}

      # Deep comparison (collect all differences)
      iex> map1 = %{a: 1, b: 2, c: 3, d: %{e: 4, f: 5}}
      iex> map2 = %{a: 1, b: 7, d: %{e: 9, g: 8}, h: 10}
      iex> {:error, differences} = JsonComparator.compare(map1, map2, deep_compare: true)
      iex> length(differences)
      6

      # Processing all differences
      iex> map1 = %{a: 1, b: 2, c: 3}
      iex> map2 = %{a: 1, b: 5}
      iex> {:error, _diffs} = JsonComparator.compare(map1, map2, deep_compare: true)
      {:error,
      [
        {"c", %{type: :missing_key, actual: nil, expected: 3}},
        {"b", %{type: :value_mismatch, actual: 5, expected: 2}}
      ]}
  """
  def compare(json1, json2, opts \\ []) do
    # Normalize options
    processed_opts = normalize_options(opts)

    if processed_opts[:deep_compare] do
      perform_deep_comparison(json1, json2, processed_opts)
    else
      perform_standard_comparison(json1, json2, processed_opts)
    end
  end

  defp normalize_options(opts) do
    [
      strict_list_order: Keyword.get(opts, :strict_list_order, false),
      truncate_datetime_microseconds: Keyword.get(opts, :truncate_datetime_microseconds, true),
      error_message: Keyword.get(opts, :error_message, "Submitted JSONs do not match: %{path}"),
      deep_compare: Keyword.get(opts, :deep_compare, false)
    ]
  end

  defp perform_deep_comparison(json1, json2, opts) do
    {diffs, _} = collect_all_differences(json1, json2, "", opts)

    if diffs == [] do
      :ok
    else
      {:error, diffs}
    end
  end

  defp perform_standard_comparison(json1, json2, opts) do
    case do_compare(json1, json2, opts) do
      {:ok, true} -> :ok
      {:ok, false} -> format_generic_difference(json1, json2, opts)
      {:ok, {false, path}} -> format_specific_difference(path, opts)
    end
  end

  defp format_generic_difference(json1, json2, opts) do
    path =
      if is_list(json1) and is_list(json2) do
        get_list_difference_path(json1, json2, opts)
      else
        ""
      end

    {:error, String.replace(opts[:error_message], "%{path}", path)}
  end

  defp get_list_difference_path(list1, list2, opts) do
    case find_first_list_difference(list1, list2, opts) do
      {:ok, path} when path != "" -> path
      _ -> ""
    end
  end

  defp format_specific_difference(path, opts) do
    path_str = to_string(path)
    {:error, String.replace(opts[:error_message], "%{path}", path_str)}
  end

  # Helper to find the first difference in lists when no specific path is returned
  # For lists of different lengths, we just return an empty path
  defp find_first_list_difference(list1, list2, _opts) when length(list1) != length(list2) do
    {:ok, ""}
  end

  # For lists of the same length, compare items to find differences
  defp find_first_list_difference(list1, list2, opts) do
    list1
    |> Enum.zip(list2)
    |> Enum.with_index()
    |> find_first_difference_in_items(opts)
  end

  defp find_first_difference_in_items(indexed_items, opts) do
    Enum.reduce_while(indexed_items, :error, fn {{item1, item2}, idx}, _acc ->
      case find_deepest_path_difference(item1, item2, "[#{idx}]", opts) do
        {:ok, path} -> {:halt, {:ok, path}}
        _ -> {:cont, :error}
      end
    end)
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
        # Ensure we include the full path with the index
        path_idx = if path == "", do: "[#{index}]", else: "#{path}[#{index}]"
        {diffs, _} = collect_all_differences(item1, item2, path_idx, opts)
        acc ++ diffs
      end)

    # Handle unmatched items from both lists
    unmatched_diffs1 =
      unmatched
      |> Enum.with_index(length(matched_pairs))
      |> Enum.map(fn {item, index} ->
        # Ensure consistent path formatting for array indices
        path_idx = if path == "", do: "[#{index}]", else: "#{path}[#{index}]"

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
        # Ensure consistent path formatting for array indices
        path_idx = if path == "", do: "[#{index}]", else: "#{path}[#{index}]"

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
    # For maps with an 'id' field, try to match by id first for better matching
    if is_map(item) && Map.has_key?(item, :id) do
      id_match =
        Enum.find_index(list, fn candidate ->
          is_map(candidate) && Map.has_key?(candidate, :id) && candidate.id == item.id
        end)

      if id_match != nil do
        candidate = Enum.at(list, id_match)
        new_list = List.delete_at(list, id_match)
        {:ok, candidate, new_list}
      else
        # Fall back to similarity matching
        find_most_similar_item(item, list, opts)
      end
    else
      # For other types, use similarity matching
      find_most_similar_item(item, list, opts)
    end
  end

  defp find_most_similar_item(item, list, opts) do
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

  defp do_compare(%DateTime{} = dt1, %DateTime{} = dt2, opts) do
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

  defp do_compare(%_{} = struct1, %_{} = struct2, _opts) do
    {:ok, struct1.__struct__ == struct2.__struct__ and struct1 == struct2}
  end

  defp do_compare(map1, map2, opts) when is_map(map1) and is_map(map2) do
    case Map.equal?(map1, map2) do
      false -> compare_map_keys(Map.keys(map1), Map.keys(map2), map1, map2, opts)
      _ -> {:ok, true}
    end
  end

  defp do_compare(list1, list2, opts) when is_list(list1) and is_list(list2) do
    # For lists, make sure we correctly add the path component
    case compare_lists(list1, list2, opts) do
      {:ok, {false, path}} -> {:ok, {false, path}}
      other -> other
    end
  end

  defp do_compare(val1, val2, _opts) do
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
      case do_compare(map1[key], map2[key], opts) do
        {:ok, true} -> {:cont, acc}
        {:ok, {false, path}} -> handle_path_difference(key, path)
        {:ok, false} -> {:halt, {:ok, {false, key}}}
      end
    end)
  end

  defp handle_path_difference(key, path) do
    path_str = to_string(path)
    formatted_path = format_path_with_key(key, path_str)
    {:halt, {:ok, {false, formatted_path}}}
  end

  defp format_path_with_key(key, ""), do: "#{key}"
  defp format_path_with_key(key, path) when binary_part(path, 0, 1) == "[", do: "#{key}#{path}"
  defp format_path_with_key(key, path), do: "#{key}.#{path}"

  defp compare_lists(list1, list2, opts) do
    cond do
      length(list1) != length(list2) ->
        {:ok, {false, "[#{min(length(list1), length(list2))}]"}}

      Keyword.get(opts, :strict_list_order, false) ->
        compare_lists_strict(list1, list2, opts)

      true ->
        path_result = compare_lists_unordered(list1, list2, opts)
        # Make sure to preserve the full path with array indexes
        path_result
    end
  end

  defp compare_lists_strict(list1, list2, opts) do
    list1
    |> Enum.zip(list2)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, true}, fn {{item1, item2}, index}, acc ->
      case do_compare(item1, item2, opts) do
        {:ok, true} -> {:cont, acc}
        {:ok, {false, path}} -> {:halt, {:ok, {false, "[#{index}].#{path}"}}}
        {:ok, false} -> {:halt, {:ok, {false, "[#{index}]"}}}
      end
    end)
  end

  defp compare_lists_unordered(list1, list2, opts) do
    list1 = Enum.sort_by(list1, &inspect/1)
    list2 = Enum.sort_by(list2, &inspect/1)
    compare_lists_strict(list1, list2, opts)
  end

  defp find_deepest_path_difference(item1, item2, path, opts) do
    # For maps, check each key
    cond do
      is_map(item1) and is_map(item2) and not (is_struct(item1) or is_struct(item2)) ->
        find_map_differences(item1, item2, path, opts)

      is_list(item1) and is_list(item2) ->
        find_list_differences(item1, item2, path, opts)

      true ->
        # For simple values, just check equality
        if item1 === item2 do
          :error
        else
          {:ok, path}
        end
    end
  end

  defp find_map_differences(map1, map2, path_prefix, opts) do
    # Get common keys between the maps
    common_keys = Enum.filter(Map.keys(map1), &Map.has_key?(map2, &1))

    # Check each common key for differences
    Enum.reduce_while(common_keys, :error, fn key, acc ->
      val1 = Map.get(map1, key)
      val2 = Map.get(map2, key)

      # Skip if values are identical
      if val1 === val2 do
        {:cont, acc}
      else
        # Build the new path segment
        new_path = format_map_path(path_prefix, key)
        compare_different_values(val1, val2, new_path, opts)
      end
    end)
  end

  defp format_map_path("", key), do: "#{key}"
  defp format_map_path(prefix, key), do: "#{prefix}.#{key}"

  defp compare_different_values(val1, val2, path, opts) do
    # Recursively check complex structures
    case find_deepest_path_difference(val1, val2, path, opts) do
      {:ok, path} -> {:halt, {:ok, path}}
      :error -> {:halt, {:ok, path}}
    end
  end

  defp find_list_differences(list1, list2, path_prefix, opts) do
    # Check if we have short lists of equal length
    if length(list1) == length(list2) and length(list1) <= 10 do
      # For short lists, compare item by item
      compare_list_items(list1, list2, path_prefix, opts)
    else
      # For longer lists or different lengths, just report the path
      {:ok, path_prefix}
    end
  end

  defp compare_list_items(list1, list2, path_prefix, opts) do
    Enum.reduce_while(Enum.with_index(Enum.zip(list1, list2)), :error, fn {{item1, item2}, idx}, acc ->
      new_path = if path_prefix == "", do: "[#{idx}]", else: "#{path_prefix}[#{idx}]"

      # Skip comparison if items are identical
      if item1 === item2 do
        {:cont, acc}
      else
        handle_different_list_items(item1, item2, new_path, opts)
      end
    end)
  end

  defp handle_different_list_items(item1, item2, path, opts) do
    case find_deepest_path_difference(item1, item2, path, opts) do
      {:ok, path} -> {:halt, {:ok, path}}
      :error -> {:halt, {:ok, path}}
    end
  end
end
