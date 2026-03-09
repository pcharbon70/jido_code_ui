defmodule JidoCodeUi.Runtime.StartupLifecycle do
  @moduledoc """
  Tracks startup readiness across required runtime children and emits lifecycle events.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry

  @max_events 200

  @type child_id :: atom()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  @spec expected_children() :: [child_id()]
  def expected_children do
    GenServer.call(__MODULE__, :expected_children)
  end

  @spec set_expected_children([child_id()]) :: :ok
  def set_expected_children(children) when is_list(children) do
    GenServer.call(__MODULE__, {:set_expected_children, children})
  end

  @spec mark_child_ready(child_id()) :: :ok
  def mark_child_ready(child) when is_atom(child) do
    GenServer.cast(__MODULE__, {:mark_child_ready, child})
  end

  @spec recent_events(pos_integer()) :: [map()]
  def recent_events(limit \\ 50) when is_integer(limit) and limit > 0 do
    GenServer.call(__MODULE__, {:recent_events, limit})
  end

  @impl true
  def init(opts) do
    expected_children = opts |> Keyword.get(:expected_children, []) |> MapSet.new()

    state = %{
      expected_children: expected_children,
      ready_children: MapSet.new(),
      events: [],
      startup_ready_emitted: false
    }

    {:ok,
     record_event(state, :startup_lifecycle_started, %{
       expected_children: MapSet.to_list(expected_children)
     })}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, ready_now?(state), state}
  end

  @impl true
  def handle_call(:expected_children, _from, state) do
    {:reply, MapSet.to_list(state.expected_children), state}
  end

  @impl true
  def handle_call({:set_expected_children, children}, _from, state) do
    expected_children = MapSet.new(children)

    state =
      %{state | expected_children: expected_children}
      |> record_event(:startup_expected_children_updated, %{
        expected_children: MapSet.to_list(expected_children)
      })
      |> maybe_emit_startup_ready()

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:recent_events, limit}, _from, state) do
    {:reply, state.events |> Enum.take(limit) |> Enum.reverse(), state}
  end

  @impl true
  def handle_cast({:mark_child_ready, child}, state) do
    restart_event? = MapSet.member?(state.ready_children, child)
    ready_children = MapSet.put(state.ready_children, child)

    state =
      %{state | ready_children: ready_children}
      |> record_event(
        if(restart_event?, do: :startup_child_restarted, else: :startup_child_ready),
        %{
          child: child,
          ready_children: MapSet.to_list(ready_children)
        }
      )
      |> maybe_emit_startup_ready()

    {:noreply, state}
  end

  defp ready_now?(state) do
    MapSet.subset?(state.expected_children, state.ready_children)
  end

  defp maybe_emit_startup_ready(state) do
    if ready_now?(state) and not state.startup_ready_emitted do
      state
      |> Map.put(:startup_ready_emitted, true)
      |> record_event(:startup_ready, %{
        expected_children: MapSet.to_list(state.expected_children),
        ready_children: MapSet.to_list(state.ready_children)
      })
    else
      state
    end
  end

  defp record_event(state, event, extra_metadata) do
    metadata =
      Map.merge(
        %{
          event: event,
          timestamp: DateTime.utc_now(),
          correlation_id: "cor-" <> Integer.to_string(System.unique_integer([:positive])),
          request_id: "req-" <> Integer.to_string(System.unique_integer([:positive]))
        },
        extra_metadata
      )

    Telemetry.emit("runtime.startup.#{event}", metadata)

    events = [metadata | state.events] |> Enum.take(@max_events)
    %{state | events: events}
  end
end
