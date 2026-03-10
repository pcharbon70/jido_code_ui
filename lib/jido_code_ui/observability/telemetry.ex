defmodule JidoCodeUi.Observability.Telemetry do
  @moduledoc """
  Lightweight telemetry emitter used by runtime startup and service lifecycle hooks.
  """

  alias JidoCodeUi.Observability.RedactionPolicy
  alias JidoCodeUi.TypedError

  require Logger

  @events_table :jido_code_ui_telemetry_events
  @max_events 5000
  @session_join_key_events MapSet.new([
                             "ui.session.transition.v1",
                             "ui.session.failure.v1",
                             "ui.session.retention.applied.v1",
                             "ui.session.replay.completed.v1",
                             "ui.session.replay.parity.v1",
                             "ui.session.replay.metric.v1",
                             "ui.event_projection.projected.v1",
                             "ui.event_projection.admitted.v1",
                             "ui.render.event.round_trip.v1"
                           ])
  @version_regex ~r/\.v(\d+)$/

  @spec emit(String.t(), map()) :: :ok
  def emit(event_name, metadata) when is_binary(event_name) and is_map(metadata) do
    {normalized_metadata, redaction_report} =
      metadata
      |> ensure_continuity(event_name)
      |> put_event_version(event_name)
      |> apply_redaction()

    event =
      normalized_metadata
      |> Map.put(:event_name, event_name)
      |> Map.put_new(:emitted_at, DateTime.utc_now())

    record_event(event)
    emit_contract_diagnostics(event_name, event)
    emit_typed_error_diagnostics(event_name, event)
    emit_redaction_diagnostics(event_name, event, redaction_report)
    Logger.debug(fn -> "#{event_name} #{inspect(normalized_metadata)}" end)
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

  defp ensure_continuity(metadata, event_name) do
    if ui_event?(event_name) do
      correlation_id =
        normalize_string(get_value(metadata, :correlation_id)) ||
          default_id("cor")

      request_id =
        normalize_string(get_value(metadata, :request_id)) ||
          default_id("req")

      metadata
      |> Map.put(:correlation_id, correlation_id)
      |> Map.put(:request_id, request_id)
    else
      metadata
    end
  end

  defp put_event_version(metadata, event_name) do
    case Regex.run(@version_regex, event_name, capture: :all_but_first) do
      [version_number] ->
        version = "v" <> version_number
        Map.put_new(metadata, :event_schema_version, version)

      _ ->
        metadata
    end
  end

  defp record_event(event) do
    table = ensure_table!()
    key = System.unique_integer([:positive, :monotonic])
    :ets.insert(table, {key, event})
    trim_table(table)
    :ok
  end

  defp emit_contract_diagnostics(event_name, event) do
    required_keys = required_keys_for_event(event_name, event)
    missing_keys = missing_keys(event, required_keys)

    if missing_keys != [] do
      diagnostic = %{
        event_name: "ui.telemetry.validation.failed.v1",
        source_event: event_name,
        error_code: "observability_event_missing_keys",
        error_category: "observability",
        error_stage: "telemetry_contract_validation",
        missing_keys: missing_keys,
        expected_keys: required_keys,
        correlation_id: get_value(event, :correlation_id),
        request_id: get_value(event, :request_id),
        emitted_at: DateTime.utc_now()
      }

      record_event(diagnostic)

      Logger.debug(fn ->
        "ui.telemetry.validation.failed.v1 #{inspect(Map.drop(diagnostic, [:event_name]))}"
      end)
    end

    :ok
  end

  defp emit_typed_error_diagnostics(event_name, event) do
    error_code = normalize_string(get_value(event, :error_code))

    error_category =
      normalize_string(get_value(event, :error_category)) ||
        normalize_string(get_value(event, :category))

    error_stage =
      normalize_string(get_value(event, :error_stage)) ||
        normalize_string(get_value(event, :stage))

    if error_code && error_category && error_stage do
      conformance = TypedError.conformance(error_code, error_category, error_stage)
      status = conformance_status(conformance.status)

      emit_diagnostic_event("ui.typed_error.conformance.v1", %{
        source_event: event_name,
        error_code: error_code,
        error_category: error_category,
        error_stage: error_stage,
        status: status,
        expected_category: conformance.expected_category,
        expected_stage_prefix: conformance.expected_stage_prefix,
        correlation_id: get_value(event, :correlation_id),
        request_id: get_value(event, :request_id)
      })

      emit_diagnostic_event("ui.typed_error.metric.v1", %{
        metric: "typed_error_total",
        value: 1,
        status: status,
        error_code: error_code,
        error_category: error_category,
        error_stage: error_stage,
        correlation_id: get_value(event, :correlation_id),
        request_id: get_value(event, :request_id)
      })

      if conformance.status == :fail do
        emit_diagnostic_event("ui.typed_error.metric.v1", %{
          metric: "typed_error_conformance_failures_total",
          value: 1,
          status: status,
          error_code: error_code,
          error_category: error_category,
          error_stage: error_stage,
          correlation_id: get_value(event, :correlation_id),
          request_id: get_value(event, :request_id)
        })
      end
    end

    :ok
  end

  defp emit_redaction_diagnostics(event_name, event, redaction_report) do
    if redaction_report.redaction_applied do
      emit_diagnostic_event("ui.redaction.applied.v1", %{
        source_event: event_name,
        redaction_policy_version: redaction_report.redaction_policy_version,
        redacted_field_count: length(redaction_report.redacted_fields),
        redacted_fields: redaction_report.redacted_fields,
        correlation_id: get_value(event, :correlation_id),
        request_id: get_value(event, :request_id)
      })
    end

    if redaction_report.misses != [] do
      emit_diagnostic_event("ui.redaction.miss.v1", %{
        source_event: event_name,
        redaction_policy_version: redaction_report.redaction_policy_version,
        missed_paths: redaction_report.misses,
        missed_count: length(redaction_report.misses),
        error_code: "redaction_policy_miss",
        error_category: "observability",
        error_stage: "telemetry_redaction",
        correlation_id: get_value(event, :correlation_id),
        request_id: get_value(event, :request_id)
      })
    end

    :ok
  end

  defp emit_diagnostic_event(event_name, metadata) do
    diagnostic =
      metadata
      |> Map.put(:event_name, event_name)
      |> Map.put_new(:event_schema_version, "v1")
      |> Map.put_new(:emitted_at, DateTime.utc_now())

    record_event(diagnostic)
    Logger.debug(fn -> "#{event_name} #{inspect(metadata)}" end)
    :ok
  end

  defp required_keys_for_event("ui.command.received.v1", event) do
    base_keys =
      if ui_event?("ui.command.received.v1"), do: [:correlation_id, :request_id], else: []

    case normalize_string(get_value(event, :envelope_kind)) do
      "widget_ui_event" ->
        base_keys

      _ ->
        base_keys ++ [:session_id]
    end
  end

  defp required_keys_for_event(event_name, _event) do
    base_keys =
      if ui_event?(event_name), do: [:correlation_id, :request_id], else: []

    if MapSet.member?(@session_join_key_events, event_name) do
      base_keys ++ [:session_id]
    else
      base_keys
    end
  end

  defp missing_keys(_event, []), do: []

  defp missing_keys(event, keys) do
    keys
    |> Enum.reject(fn key -> present?(event, key) end)
    |> Enum.map(&Atom.to_string/1)
  end

  defp present?(map, key) do
    case normalize_string(get_value(map, key)) do
      nil -> false
      _value -> true
    end
  end

  defp ui_event?(event_name) do
    String.starts_with?(event_name, "ui.") and
      not String.starts_with?(event_name, "ui.telemetry.")
  end

  defp conformance_status(:pass), do: "pass"
  defp conformance_status(:fail), do: "fail"
  defp conformance_status(_status), do: "unknown"

  defp apply_redaction(metadata) do
    RedactionPolicy.redact(metadata)
  end

  defp get_value(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      Map.get(map, Atom.to_string(key))
    end
  end

  defp get_value(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_string()
  end

  defp normalize_string(_value), do: nil

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
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
