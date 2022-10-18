defmodule GenDebouncerIntegrationTest do
  use ExUnit.Case, async: false

  defmodule Worker do
    @behaviour GenDebouncer

    @impl GenDebouncer
    def work(key, payload) do
      send(GenDebouncerIntegrationTest, {key, payload})
    end
  end

  test "Integration test" do
    Process.register(self(), __MODULE__)
    # the interval here must be long enough to catch bugs
    # related to time units.
    {:ok, pid} = GenDebouncer.start_link(Worker, 1000)

    batch1 =
      [6, 7, 2, 8, 2, 10, 10, 6, 3, 3, 7, 8, 1, 5, 4] ++
        [9, 4, 8, 4, 1, 3, 7, 9, 10, 4, 8, 4, 8]

    batch2 =
      [3, 6, 1, 6, 9, 9, 1, 9, 5, 10, 1, 7, 3, 9, 4, 3] ++
        [5, 2, 7, 8, 4, 9, 6, 6, 2, 1, 2, 9, 5, 9]

    batch3 = [10, 6, 2, 5, 6, 6, 7, 4, 9, 9, 2, 2, 5, 9, 8, 4, 9, 9, 1, 4]

    [
      {1, batch1},
      {2, batch2},
      {3, batch3}
    ]
    |> Enum.each(fn {key, batch} -> GenDebouncer.schedule_work_batch(pid, key, batch) end)

    refute_receive _, 1000
    assert_receive {1, set_1}, 3000
    assert set_1 == MapSet.new([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

    assert_receive {2, set_2}, 3000
    assert set_2 == MapSet.new([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

    assert_receive {3, set_3}, 3000
    assert set_3 == MapSet.new([1, 2, 4, 5, 6, 7, 8, 9, 10])
  end
end
