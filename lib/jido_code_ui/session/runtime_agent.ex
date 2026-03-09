defmodule JidoCodeUi.Session.RuntimeAgent do
  @moduledoc """
  Startup-ready session runtime authority placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :session_runtime_agent

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec create_session(map()) :: {:ok, map()} | {:error, TypedError.t()}
  def create_session(attrs \\ %{}) when is_map(attrs) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_create", %{operation: "create_session"}) do
      GenServer.call(__MODULE__, {:create_session, attrs})
    end
  end

  @spec update_session(String.t(), map()) :: {:ok, map()} | {:error, TypedError.t()}
  def update_session(session_id, attrs) when is_binary(session_id) and is_map(attrs) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_update", %{operation: "update_session"}) do
      GenServer.call(__MODULE__, {:update_session, session_id, attrs})
    end
  end

  @spec replay_session(String.t(), list()) :: {:ok, map()} | {:error, TypedError.t()}
  def replay_session(session_id, event_stream)
      when is_binary(session_id) and is_list(event_stream) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_replay", %{operation: "replay_session"}) do
      GenServer.call(__MODULE__, {:replay_session, session_id, event_stream})
    end
  end

  @spec current_snapshot(String.t()) :: {:ok, map()} | {:error, TypedError.t()}
  def current_snapshot(session_id) when is_binary(session_id) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_snapshot", %{operation: "current_snapshot"}) do
      GenServer.call(__MODULE__, {:current_snapshot, session_id})
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:create_session, attrs}, _from, state) do
    session_id =
      Map.get(attrs, :session_id) ||
        Map.get(attrs, "session_id") ||
        "sess-" <> Integer.to_string(System.unique_integer([:positive]))

    snapshot =
      attrs
      |> Map.new()
      |> Map.put(:session_id, session_id)
      |> Map.put_new(:created_at, DateTime.utc_now())

    state = put_in(state, [:sessions, session_id], snapshot)
    {:reply, {:ok, snapshot}, state}
  end

  @impl true
  def handle_call({:update_session, session_id, attrs}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, existing_snapshot} ->
        updated_snapshot =
          existing_snapshot
          |> Map.merge(Map.new(attrs))
          |> Map.put(:updated_at, DateTime.utc_now())

        state = put_in(state, [:sessions, session_id], updated_snapshot)
        {:reply, {:ok, updated_snapshot}, state}

      :error ->
        {:reply, {:error, not_found_error(session_id)}, state}
    end
  end

  @impl true
  def handle_call({:replay_session, session_id, _event_stream}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, snapshot} ->
        replayed_snapshot = Map.put(snapshot, :replayed_at, DateTime.utc_now())
        {:reply, {:ok, replayed_snapshot}, state}

      :error ->
        {:reply, {:error, not_found_error(session_id)}, state}
    end
  end

  @impl true
  def handle_call({:current_snapshot, session_id}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, snapshot} -> {:reply, {:ok, snapshot}, state}
      :error -> {:reply, {:error, not_found_error(session_id)}, state}
    end
  end

  defp not_found_error(session_id) do
    TypedError.new(
      error_code: "session_not_found",
      category: "session",
      stage: "session_runtime_lookup",
      retryable: false,
      message: "Session snapshot was not found",
      details: %{session_id: session_id},
      correlation_id: "cor-" <> Integer.to_string(System.unique_integer([:positive])),
      request_id: "req-" <> Integer.to_string(System.unique_integer([:positive]))
    )
  end
end
