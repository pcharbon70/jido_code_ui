defmodule JidoCodeUi.Session.RuntimeAgent do
  @moduledoc """
  Startup-ready session runtime authority placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupLifecycle

  @ready_child_id :session_runtime_agent

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end
end
