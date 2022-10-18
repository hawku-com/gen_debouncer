defmodule GenDebouncer.State do
  @moduledoc false
  @enforce_keys [:worker, :interval]
  defstruct @enforce_keys ++ [waiting_list: %{}]

  @type t :: %__MODULE__{
          worker: module(),
          interval: non_neg_integer(),
          waiting_list: %{any() => GenDebouncer.Fragment.t()}
        }

  alias GenDebouncer.Fragment

  @spec add_work(t(), any, any) :: t()
  def add_work(state, key, payload) do
    fragment = state.waiting_list[key] || Fragment.new()
    updated_fragment = Fragment.add_payload(fragment, payload)

    %__MODULE__{
      state
      | waiting_list: Map.put(state.waiting_list, key, updated_fragment)
    }
  end

  @spec add_work_batch(t(), any, [any()]) :: t()
  def add_work_batch(state, key, payloads) when is_list(payloads) do
    fragment = state.waiting_list[key] || Fragment.new()
    updated_fragment = Fragment.add_payloads(fragment, payloads)

    %__MODULE__{
      state
      | waiting_list: Map.put(state.waiting_list, key, updated_fragment)
    }
  end

  @spec work_to_schedule(t()) :: [{any(), MapSet.t()}]
  def work_to_schedule(state) do
    state.waiting_list
    |> Enum.filter(fn {_key, fragment} ->
      Fragment.stale?(fragment, state.interval)
    end)
    |> Enum.map(fn {key, fragment} -> {key, fragment.payloads} end)
  end

  @spec clean_work(t(), list) :: t()
  def clean_work(state, keys) do
    %__MODULE__{state | waiting_list: Map.drop(state.waiting_list, keys)}
  end
end
