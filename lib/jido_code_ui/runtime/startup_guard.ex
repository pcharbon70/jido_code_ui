defmodule JidoCodeUi.Runtime.StartupGuard do
  @moduledoc """
  Shared startup readiness guard for runtime service interfaces.
  """

  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @spec ensure_ready(String.t(), map()) :: :ok | {:error, TypedError.t()}
  def ensure_ready(stage, details \\ %{}) when is_binary(stage) and is_map(details) do
    if StartupLifecycle.ready?() do
      :ok
    else
      {:error,
       TypedError.readiness("Runtime startup is not ready yet",
         stage: stage,
         details: details
       )}
    end
  end
end
