defmodule GenDebouncer do
  use GenServer

  defmodule State do
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

  defmodule Fragment do
    @moduledoc false

    @enforce_keys [:last_updated, :payloads]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            last_updated: DateTime.t(),
            payloads: MapSet.t()
          }

    # This is needed to initialize datetime properly.
    # If used struct defaults it would start with
    # the same datetime from compilation time.
    @spec new :: t()
    def new do
      %__MODULE__{
        last_updated: DateTime.utc_now(),
        payloads: MapSet.new()
      }
    end

    @spec add_payload(t(), any) :: t()
    def add_payload(fragment, payload) do
      fragment.payloads
      |> MapSet.put(payload)
      |> replace_payloads(fragment)
    end

    @spec add_payloads(t(), any) :: t()
    def add_payloads(fragment, payloads) do
      payloads = MapSet.new(payloads)

      fragment.payloads
      |> MapSet.union(payloads)
      |> replace_payloads(fragment)
    end

    defp replace_payloads(payloads, fragment) do
      %__MODULE__{
        fragment
        | payloads: payloads
      }
    end

    @spec stale?(t(), non_neg_integer()) :: boolean()
    def stale?(fragment, interval) do
      now = DateTime.utc_now()

      DateTime.diff(now, fragment.last_updated) |> abs() > interval and
        not Enum.empty?(fragment.payloads)
    end
  end

  @callback work(key :: any(), payload :: [any()]) :: :ok

  @spec start_link(module(), non_neg_integer(), GenServer.options()) ::
          GenServer.on_start()
  def start_link(worker, interval, opts \\ []) do
    GenServer.start_link(__MODULE__, {worker, interval}, opts)
  end

  @spec schedule_work(debouncer :: GenServer.name(), key :: any(), payload :: any()) ::
          :ok | {:error, term()}
  def schedule_work(debouncer, key, payload) do
    GenServer.cast(debouncer, {:schedule_work, payload, key})
  end

  @spec schedule_work_batch(debouncer :: GenServer.name(), key :: any(), payload :: [any()]) ::
          :ok | {:error, term()}
  def schedule_work_batch(debouncer, key, payloads) do
    GenServer.cast(debouncer, {:schedule_work_batch, payloads, key})
  end

  # -----
  # GenServer Api implementation
  # -----

  @impl GenServer
  def init({worker, interval}) do
    state = %State{
      worker: worker,
      interval: interval
    }

    :timer.send_interval(interval, self(), :tick)

    {:ok, state}
  end

  @impl true
  def handle_cast({:schedule_work, payload, key}, state) do
    {:noreply, State.add_work(state, key, payload)}
  end

  def handle_cast({:schedule_work_batch, payloads, key}, state) do
    {:noreply, State.add_work_batch(state, key, payloads)}
  end

  @impl true
  def handle_info(:tick, state) do
    workload = State.work_to_schedule(state)

    Enum.each(workload, fn {key, payloads} ->
      state.worker.work(key, payloads)
    end)

    state = State.clean_work(state, Enum.map(workload, &elem(&1, 0)))

    {:noreply, state}
  end
end
