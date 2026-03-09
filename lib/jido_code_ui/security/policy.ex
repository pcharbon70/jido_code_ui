defmodule JidoCodeUi.Security.Policy do
  @moduledoc """
  Startup-ready policy runtime service.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupLifecycle

  @ready_child_id :security_policy

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec authorize(map(), map()) :: {:ok, map()} | {:error, map()}
  def authorize(_context, _command) do
    {:ok, %{decision: :allow, policy_version: "v1"}}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end
end
