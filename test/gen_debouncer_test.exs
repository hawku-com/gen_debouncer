defmodule GenDebouncerTest do
  use ExUnit.Case, async: true

  @complex_payload %{a: 2, b: 1}
  @simple_payload :simple_payload
  @interval 1
  @worker __MODULE__.Worker

  defmodule Worker do
    @behaviour GenDebouncer

    @impl GenDebouncer
    def work(key, payload) do
      send(self(), {key, payload})
    end
  end

  test "init" do
    assert {:ok, state} = GenDebouncer.init({@worker, @interval})
    assert state == %GenDebouncer.State{worker: @worker, interval: @interval}
    assert_receive :tick, @interval * 3
  end

  describe "handle_cast, key does not exist" do
    setup do
      [state: %GenDebouncer.State{worker: @worker, interval: @interval}]
    end

    test "adds single payload to the state", %{state: state} do
      result = GenDebouncer.handle_cast({:schedule_work, @complex_payload, :key}, state)
      assert {:noreply, result_state} = result
      assert MapSet.new([@complex_payload]) == result_state.waiting_list[:key].payloads
    end

    test "adds payload batch to the state", %{state: state} do
      payloads = [@complex_payload, @simple_payload]
      result = GenDebouncer.handle_cast({:schedule_work_batch, payloads, :key}, state)
      assert {:noreply, result_state} = result

      assert MapSet.new([@complex_payload, @simple_payload]) ==
               result_state.waiting_list[:key].payloads
    end
  end

  describe "handle_cast, key already exists" do
    setup do
      waiting_list = %{
        key: %GenDebouncer.Fragment{
          last_updated: ~U"2022-10-09 10:21:16.711564Z",
          payloads: MapSet.new([%{a: 2, b: 1}])
        }
      }

      [state: %GenDebouncer.State{worker: @worker, interval: 1, waiting_list: waiting_list}]
    end

    test "does not duplicate payload when adding single one", %{state: state} do
      result = GenDebouncer.handle_cast({:schedule_work, @complex_payload, :key}, state)
      assert {:noreply, result_state} = result
      assert MapSet.new([@complex_payload]) == result_state.waiting_list[:key].payloads
    end

    test "does not duplicate payload when adding multiple", %{state: state} do
      payloads = [@complex_payload, @simple_payload]
      result = GenDebouncer.handle_cast({:schedule_work_batch, payloads, :key}, state)
      assert {:noreply, result_state} = result

      assert MapSet.new([@complex_payload, @simple_payload]) ==
               result_state.waiting_list[:key].payloads
    end
  end

  test "handle_info" do
    waiting_list = %{
      key: %GenDebouncer.Fragment{
        last_updated: ~U"2022-10-09 10:21:16.711564Z",
        payloads: MapSet.new([@complex_payload, @simple_payload])
      }
    }

    state = %GenDebouncer.State{worker: @worker, interval: 1, waiting_list: waiting_list}

    assert {:noreply, new_state} = GenDebouncer.handle_info(:tick, state)
    assert_receive {:key, %MapSet{map: %{:simple_payload => [], %{a: 2, b: 1} => []}}}
    assert new_state.waiting_list == %{}
  end
end
