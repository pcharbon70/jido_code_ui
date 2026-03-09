defmodule JidoCodeUi.Observability.Telemetry do
  @moduledoc """
  Lightweight telemetry emitter used by runtime startup and service lifecycle hooks.
  """

  require Logger

  @spec emit(String.t(), map()) :: :ok
  def emit(event_name, metadata) when is_binary(event_name) and is_map(metadata) do
    Logger.debug(fn -> "#{event_name} #{inspect(metadata)}" end)
    :ok
  end
end
