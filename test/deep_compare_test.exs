defmodule JsonComparator.DeepCompareTest do
  use ExUnit.Case

  describe "deep comparison option" do
    test "returns all differences in maps with deep_compare: true" do
      map1 = %{a: 1, b: 2, c: 3, d: %{e: 4, f: 5}}
      map2 = %{a: 1, b: 7, d: %{e: 9, g: 8}, h: 10}

      assert :ok == JsonComparator.compare(map1, map1, deep_compare: true)

      assert {:error, diffs} = JsonComparator.compare(map1, map2, deep_compare: true)
      # b, c, d.e, d.f, d.g, h differences
      assert length(diffs) == 6

      # Convert the list to a map for easier testing
      diff_map = Enum.into(diffs, %{}, fn {path, details} -> {path, details} end)

      # Check specific differences
      assert diff_map["b"][:expected] == 2
      assert diff_map["b"][:actual] == 7
      assert diff_map["b"][:type] == :value_mismatch

      assert diff_map["c"][:expected] == 3
      assert diff_map["c"][:actual] == nil
      assert diff_map["c"][:type] == :missing_key

      assert diff_map["d.e"][:expected] == 4
      assert diff_map["d.e"][:actual] == 9
      assert diff_map["d.e"][:type] == :value_mismatch

      assert diff_map["d.f"][:expected] == 5
      assert diff_map["d.f"][:actual] == nil
      assert diff_map["d.f"][:type] == :missing_key

      assert diff_map["d.g"][:expected] == nil
      assert diff_map["d.g"][:actual] == 8
      assert diff_map["d.g"][:type] == :extra_key

      assert diff_map["h"][:expected] == nil
      assert diff_map["h"][:actual] == 10
      assert diff_map["h"][:type] == :extra_key
    end

    test "returns all differences in lists with deep_compare: true" do
      list1 = [1, 2, 3, 4]
      list2 = [1, 5, 6, 7]

      assert {:error, diffs} = JsonComparator.compare(list1, list2, strict_list_order: true, deep_compare: true)
      # Differences at indices 1, 2, 3
      assert length(diffs) == 3

      diff_map = Enum.into(diffs, %{}, fn {path, details} -> {path, details} end)

      assert diff_map["[1]"][:expected] == 2
      assert diff_map["[1]"][:actual] == 5
      assert diff_map["[2]"][:expected] == 3
      assert diff_map["[2]"][:actual] == 6
      assert diff_map["[3]"][:expected] == 4
      assert diff_map["[3]"][:actual] == 7
    end

    test "returns all differences in nested structures with deep_compare: true" do
      complex1 = %{
        user: %{
          name: "Alice",
          roles: ["admin", "editor"],
          settings: %{
            theme: "dark",
            notifications: true
          }
        }
      }

      complex2 = %{
        user: %{
          name: "Bob",
          roles: ["editor", "viewer"],
          settings: %{
            theme: "light",
            language: "en"
          }
        }
      }

      assert {:error, diffs} = JsonComparator.compare(complex1, complex2, deep_compare: true)
      # Multiple differences expected
      assert length(diffs) >= 5

      diff_map = Enum.into(diffs, %{}, fn {path, details} -> {path, details} end)

      assert diff_map["user.name"][:expected] == "Alice"
      assert diff_map["user.name"][:actual] == "Bob"
      assert diff_map["user.settings.theme"][:expected] == "dark"
      assert diff_map["user.settings.theme"][:actual] == "light"
      assert diff_map["user.settings.notifications"][:type] == :missing_key
      assert diff_map["user.settings.language"][:type] == :extra_key
    end
  end
end
