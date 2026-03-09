defmodule JidoCodeUi.Runtime.Substrate do
  @moduledoc """
  Runtime ingress substrate with startup readiness gating.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :runtime_substrate

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec admit(map()) :: {:ok, map()} | {:error, TypedError.t()}
  def admit(envelope) when is_map(envelope) do
    if StartupLifecycle.ready?() do
      {:ok, normalize_envelope(envelope)}
    else
      {:error,
       TypedError.readiness("Runtime is not ready for ingress admission",
         stage: "ingress_admission"
       )}
    end
  end

  def admit(_invalid_payload) do
    {:error, TypedError.readiness("Ingress envelope must be a map", stage: "ingress_admission")}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp normalize_envelope(envelope) do
    correlation_id = get_key(envelope, :correlation_id)
    request_id = get_key(envelope, :request_id)

    envelope
    |> Map.put_new(:correlation_id, correlation_id || default_id("cor"))
    |> Map.put_new(:request_id, request_id || default_id("req"))
    |> Map.put_new(:admitted_at, DateTime.utc_now())
  end

  defp get_key(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
