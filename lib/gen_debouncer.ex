defmodule GenDebouncer do
  @moduledoc """
  GenDebouncer for all debouncing and batching needs.
  """
  use GenServer

  alias GenDebouncer.State

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
