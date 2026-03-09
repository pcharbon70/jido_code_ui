defmodule JidoCodeUi.Services.UiOrchestrator do
  @moduledoc """
  Startup-ready orchestrator service placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :ui_orchestrator

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec execute(map(), map()) :: {:ok, map()} | {:error, TypedError.t()}
  def execute(command, context \\ %{}) when is_map(context) do
    with :ok <- StartupGuard.ensure_ready("orchestrator_execute", %{operation: "execute"}) do
      {:ok, %{command: command, context: context, status: :accepted}}
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end
end
