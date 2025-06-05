defmodule JsonComparatorTest do
  use ExUnit.Case
  doctest JsonComparator

  describe "basic comparisons" do
    test "compares simple values" do
      assert :ok == JsonComparator.compare(1, 1)
      assert :ok == JsonComparator.compare("test", "test")
      assert :ok == JsonComparator.compare(true, true)
      assert :ok == JsonComparator.compare(nil, nil)
    end

    test "detects differences in simple values" do
      assert {:error, "Submitted JSONs do not match: "} = JsonComparator.compare(1, 2)
      assert {:error, "Submitted JSONs do not match: "} = JsonComparator.compare("test", "other")
      assert {:error, "Submitted JSONs do not match: "} = JsonComparator.compare(true, false)
    end
  end

  describe "map comparisons" do
    test "compares flat maps" do
      assert :ok == JsonComparator.compare(%{a: 1, b: 2}, %{a: 1, b: 2})
    end

    test "compares nested maps" do
      map1 = %{a: %{b: %{c: 1}}}
      map2 = %{a: %{b: %{c: 1}}}
      assert :ok == JsonComparator.compare(map1, map2)
    end

    test "detects differences in nested maps" do
      map1 = %{a: %{b: %{c: 1}}}
      map2 = %{a: %{b: %{c: 2}}}
      assert {:error, "Submitted JSONs do not match: a.b.c"} = JsonComparator.compare(map1, map2)
    end

    test "detects missing keys" do
      map1 = %{a: 1, b: 2}
      map2 = %{a: 1}
      assert {:error, "Submitted JSONs do not match: b"} = JsonComparator.compare(map1, map2)
    end
  end

  describe "list comparisons" do
    test "compares lists with default unordered comparison" do
      assert :ok == JsonComparator.compare([1, 2, 3], [3, 2, 1])
      assert :ok == JsonComparator.compare([%{a: 1}, %{b: 2}], [%{b: 2}, %{a: 1}])
    end

    test "compares lists with strict ordering" do
      assert :ok == JsonComparator.compare([1, 2, 3], [1, 2, 3], strict_list_order: true)

      assert {:error, "Submitted JSONs do not match: [0]"} =
               JsonComparator.compare([1, 2, 3], [3, 2, 1], strict_list_order: true)
    end

    test "detects different list lengths" do
      assert {:error, "Submitted JSONs do not match: [2]"} =
               JsonComparator.compare([1, 2, 3], [1, 2])
    end

    test "compares nested lists" do
      assert :ok ==
               JsonComparator.compare(
                 [1, [2, 3], 4],
                 [4, [3, 2], 1]
               )
    end
  end

  describe "DateTime comparisons" do
    test "compares DateTimes with microsecond truncation by default" do
      dt1 = DateTime.from_naive!(~N[2024-01-01 00:00:00.123456], "Etc/UTC")
      dt2 = DateTime.from_naive!(~N[2024-01-01 00:00:00.789012], "Etc/UTC")

      assert :ok == JsonComparator.compare(dt1, dt2)
    end

    test "compares DateTimes with exact microseconds when specified" do
      dt1 = DateTime.from_naive!(~N[2024-01-01 00:00:00.123456], "Etc/UTC")
      dt2 = DateTime.from_naive!(~N[2024-01-01 00:00:00.789012], "Etc/UTC")

      assert {:error, "Submitted JSONs do not match: "} =
               JsonComparator.compare(dt1, dt2, truncate_datetime_microseconds: false)
    end
  end

  describe "struct comparisons" do
    test "compares identical structs" do
      struct1 = %URI{path: "/test"}
      struct2 = %URI{path: "/test"}
      assert :ok == JsonComparator.compare(struct1, struct2)
    end

    test "detects different struct types" do
      struct1 = %URI{path: "/test"}
      struct2 = %Version{major: 1, minor: 0, patch: 0}
      assert {:error, "Submitted JSONs do not match: "} = JsonComparator.compare(struct1, struct2)
    end
  end

  describe "error messages" do
    test "supports custom error messages" do
      map1 = %{a: 1}
      map2 = %{a: 2}

      assert {:error, "Values differ at: a"} =
               JsonComparator.compare(map1, map2, error_message: "Values differ at: %{path}")
    end
  end

  describe "edge cases" do
    test "handles empty maps" do
      assert :ok == JsonComparator.compare(%{}, %{})
    end

    test "handles empty lists" do
      assert :ok == JsonComparator.compare([], [])
    end

    test "compares mixed data types" do
      json1 = %{
        string: "test",
        number: 42,
        list: [1, 2, 3],
        map: %{nested: true},
        date: DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC")
      }

      json2 = %{
        string: "test",
        number: 42,
        list: [3, 2, 1],
        map: %{nested: true},
        date: DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC")
      }

      assert :ok == JsonComparator.compare(json1, json2)
    end
  end
end
