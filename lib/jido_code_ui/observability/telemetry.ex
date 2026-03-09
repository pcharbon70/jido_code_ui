defmodule JidoCodeUi.Observability.Telemetry do
  @moduledoc """
  Lightweight telemetry emitter used by runtime startup and service lifecycle hooks.
  """

  require Logger

  @events_table :jido_code_ui_telemetry_events
  @max_events 300

  @spec emit(String.t(), map()) :: :ok
  def emit(event_name, metadata) when is_binary(event_name) and is_map(metadata) do
    event =
      metadata
      |> Map.put(:event_name, event_name)
      |> Map.put_new(:emitted_at, DateTime.utc_now())

    record_event(event)
    Logger.debug(fn -> "#{event_name} #{inspect(metadata)}" end)
    :ok
  end

  @spec recent_events(pos_integer()) :: [map()]
  def recent_events(limit \\ 50) when is_integer(limit) and limit > 0 do
    table = ensure_table!()

    table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _event} -> key end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_key, event} -> event end)
  end

  @spec reset_events() :: :ok
  def reset_events do
    table = ensure_table!()
    :ets.delete_all_objects(table)
    :ok
  end

  defp record_event(event) do
    table = ensure_table!()
    key = System.unique_integer([:positive, :monotonic])
    :ets.insert(table, {key, event})
    trim_table(table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@events_table) do
      :undefined ->
        try do
          :ets.new(@events_table, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])
        rescue
          ArgumentError -> @events_table
        end

      _table ->
        @events_table
    end
  end

  defp trim_table(table) do
    size = :ets.info(table, :size)

    if is_integer(size) and size > @max_events do
      overflow = size - @max_events

      table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {key, _event} -> key end)
      |> Enum.take(overflow)
      |> Enum.each(fn {key, _event} -> :ets.delete(table, key) end)
    end

    :ok
  end
end
