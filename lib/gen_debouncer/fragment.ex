defmodule GenDebouncer.Fragment do
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

    DateTime.diff(now, fragment.last_updated, :millisecond) |> abs() > interval and
      not Enum.empty?(fragment.payloads)
  end
end
