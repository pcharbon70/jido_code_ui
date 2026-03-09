defmodule JidoCodeUi.Runtime.Substrate do
  @moduledoc """
  Runtime ingress substrate with startup readiness gating, schema validation, and
  envelope normalization.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :runtime_substrate
  @schema_version "v1"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec admit(map()) :: {:ok, map()} | {:error, TypedError.t()}
  def admit(envelope) when is_map(envelope) do
    with :ok <- StartupGuard.ensure_ready("ingress_admission", %{operation: "admit"}),
         {:ok, normalized_envelope} <- validate_and_normalize(envelope) do
      emit_normalization_outcome(:accepted, normalized_envelope)
      {:ok, normalized_envelope}
    else
      {:error, %TypedError{} = typed_error} ->
        emit_normalization_outcome(:rejected, typed_error)
        {:error, typed_error}
    end
  end

  def admit(invalid_payload) do
    typed_error =
      validation_error(
        %{},
        "ingress_invalid_payload",
        "Ingress envelope must be a map",
        "ingress_validation",
        %{
          schema_path: "$",
          expected: "map",
          received: inspect(invalid_payload)
        }
      )

    emit_normalization_outcome(:rejected, typed_error)
    {:error, typed_error}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp validate_and_normalize(envelope) do
    cond do
      command_envelope?(envelope) ->
        normalize_command_envelope(envelope)

      widget_event_envelope?(envelope) ->
        normalize_widget_event_envelope(envelope)

      true ->
        {:error,
         validation_error(
           envelope,
           "ingress_schema_invalid",
           "Ingress payload does not match supported envelope schemas",
           "ingress_validation",
           %{
             schema_path: "$",
             expected: "UiCommand or WidgetUiEventEnvelope",
             received_keys: envelope |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
           }
         )}
    end
  end

  defp normalize_command_envelope(envelope) do
    with {:ok, command_type} <-
           required_string(envelope, :command_type, "$.command_type", "UiCommand.command_type"),
         {:ok, session_id} <-
           required_string(envelope, :session_id, "$.session_id", "UiCommand.session_id"),
         {:ok, payload} <-
           optional_map(envelope, :payload, "$.payload", "UiCommand.payload", %{}) do
      correlation_id = get_key(envelope, :correlation_id) || default_id("cor")
      request_id = get_key(envelope, :request_id) || default_id("req")

      {:ok,
       %{
         envelope_kind: :ui_command,
         schema_version: @schema_version,
         correlation_id: correlation_id,
         request_id: request_id,
         admitted_at: DateTime.utc_now(),
         ui_command: %{
           command_type: command_type,
           session_id: session_id,
           payload: payload
         },
         dispatch_context: %{
           correlation_id: correlation_id,
           request_id: request_id,
           session_id: session_id
         }
       }}
    end
  end

  defp normalize_widget_event_envelope(envelope) do
    with {:ok, event_type} <-
           required_string(envelope, :type, "$.type", "WidgetUiEventEnvelope.type"),
         {:ok, widget_id} <-
           required_string(envelope, :widget_id, "$.widget_id", "WidgetUiEventEnvelope.widget_id"),
         {:ok, data} <- optional_map(envelope, :data, "$.data", "WidgetUiEventEnvelope.data", %{}) do
      correlation_id = get_key(envelope, :correlation_id) || default_id("cor")
      request_id = get_key(envelope, :request_id) || default_id("req")
      widget_kind = optional_string(envelope, :widget_kind, "unknown_widget")
      timestamp = optional_timestamp(envelope, :timestamp)

      {:ok,
       %{
         envelope_kind: :widget_ui_event,
         schema_version: @schema_version,
         correlation_id: correlation_id,
         request_id: request_id,
         admitted_at: DateTime.utc_now(),
         widget_ui_event: %{
           type: event_type,
           widget_id: widget_id,
           widget_kind: widget_kind,
           timestamp: timestamp,
           data: data
         },
         dispatch_context: %{
           correlation_id: correlation_id,
           request_id: request_id,
           widget_id: widget_id
         }
       }}
    end
  end

  defp command_envelope?(envelope) do
    has_key?(envelope, :command_type) or has_key?(envelope, :session_id)
  end

  defp widget_event_envelope?(envelope) do
    has_key?(envelope, :type) and has_key?(envelope, :widget_id)
  end

  defp has_key?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp get_key(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp required_string(envelope, key, schema_path, expected_label) do
    case get_key(envelope, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          {:ok, trimmed}
        else
          {:error,
           validation_error(
             envelope,
             "ingress_schema_invalid",
             "#{expected_label} must be a non-empty string",
             "ingress_validation",
             %{
               schema_path: schema_path,
               expected: "non-empty string",
               received: inspect(value)
             }
           )}
        end

      invalid ->
        {:error,
         validation_error(
           envelope,
           "ingress_schema_invalid",
           "#{expected_label} must be a non-empty string",
           "ingress_validation",
           %{
             schema_path: schema_path,
             expected: "non-empty string",
             received: inspect(invalid)
           }
         )}
    end
  end

  defp optional_map(envelope, key, schema_path, expected_label, default) do
    case get_key(envelope, key) do
      nil ->
        {:ok, default}

      value when is_map(value) ->
        {:ok, value}

      invalid ->
        {:error,
         validation_error(
           envelope,
           "ingress_schema_invalid",
           "#{expected_label} must be a map",
           "ingress_validation",
           %{
             schema_path: schema_path,
             expected: "map",
             received: inspect(invalid)
           }
         )}
    end
  end

  defp optional_string(envelope, key, default) do
    case get_key(envelope, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          trimmed
        else
          default
        end

      _ ->
        default
    end
  end

  defp optional_timestamp(envelope, key) do
    case get_key(envelope, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          trimmed
        else
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        end

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    end
  end

  defp validation_error(envelope, error_code, message, stage, details) do
    {correlation_id, request_id} = continuity_ids_from(envelope)

    TypedError.new(
      error_code: error_code,
      category: "validation",
      stage: stage,
      retryable: false,
      message: message,
      details: details,
      correlation_id: correlation_id,
      request_id: request_id
    )
  end

  defp continuity_ids_from(envelope) do
    correlation_id = get_key(envelope, :correlation_id)
    request_id = get_key(envelope, :request_id)
    {normalize_or_default_id(correlation_id, "cor"), normalize_or_default_id(request_id, "req")}
  end

  defp normalize_or_default_id(value, prefix) when is_binary(value) do
    trimmed = String.trim(value)

    if byte_size(trimmed) > 0 do
      trimmed
    else
      default_id(prefix)
    end
  end

  defp normalize_or_default_id(_value, prefix), do: default_id(prefix)

  defp emit_normalization_outcome(:accepted, normalized_envelope) do
    Telemetry.emit("ui.ingress.normalization.v1", %{
      outcome: "accepted",
      envelope_kind: to_string(normalized_envelope.envelope_kind),
      schema_version: normalized_envelope.schema_version,
      correlation_id: normalized_envelope.correlation_id,
      request_id: normalized_envelope.request_id
    })
  end

  defp emit_normalization_outcome(:rejected, %TypedError{} = typed_error) do
    Telemetry.emit("ui.ingress.normalization.v1", %{
      outcome: "rejected",
      error_code: typed_error.error_code,
      category: typed_error.category,
      stage: typed_error.stage,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id
    })
  end

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
