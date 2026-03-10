defmodule JidoCodeUi.Runtime.Substrate do
  @moduledoc """
  Runtime ingress substrate with startup readiness gating, schema validation, and
  envelope normalization.
  """

  use GenServer

  alias JidoCodeUi.Contracts.UiCommand
  alias JidoCodeUi.Contracts.WidgetUiEventEnvelope
  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :runtime_substrate
  @schema_version "v1"
  @continuity_stage "ingress_continuity"
  @auth_stage "ingress_auth"
  @continuity_id_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec admit(map()) :: {:ok, map()} | {:error, TypedError.t()}
  def admit(envelope) when is_map(envelope) do
    with :ok <- StartupGuard.ensure_ready("ingress_admission", %{operation: "admit"}),
         {:ok, normalized_envelope} <- validate_and_normalize(envelope) do
      emit_admitted_ingress(normalized_envelope)
      emit_continuity_check(:accepted, normalized_envelope)
      emit_normalization_outcome(:accepted, normalized_envelope)
      {:ok, normalized_envelope}
    else
      {:error, %TypedError{} = typed_error} ->
        emit_denied_ingress(typed_error, envelope)
        emit_continuity_check(:rejected, typed_error)
        emit_auth_denied_diagnostics(typed_error)
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

    emit_denied_ingress(typed_error, %{})
    emit_normalization_outcome(:rejected, typed_error)
    {:error, typed_error}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp validate_and_normalize(envelope) do
    with {:ok, normalized_payload} <- normalize_schema(envelope),
         {:ok, continuity_ids} <- normalize_continuity(envelope),
         {:ok, auth_context} <- normalize_auth_context(envelope, continuity_ids) do
      {:ok, attach_runtime_context(normalized_payload, continuity_ids, auth_context)}
    end
  end

  defp normalize_schema(envelope) do
    cond do
      widget_event_envelope?(envelope) ->
        normalize_widget_event_envelope(envelope)

      command_envelope?(envelope) ->
        normalize_command_envelope(envelope)

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
      {:ok,
       %{
         envelope_kind: :ui_command,
         schema_version: @schema_version,
         admitted_at: DateTime.utc_now(),
         ui_command:
           UiCommand.new(%{
             command_type: command_type,
             session_id: session_id,
             payload: payload
           }),
         dispatch_context: %{
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
      widget_kind = optional_string(envelope, :widget_kind, "unknown_widget")
      timestamp = optional_timestamp(envelope, :timestamp)

      session_id =
        optional_string(envelope, :session_id, nil) || optional_string(data, :session_id, nil)

      route_key =
        optional_string(envelope, :route_key, nil) || optional_string(data, :route_key, nil)

      render_token =
        optional_string(envelope, :render_token, nil) || optional_string(data, :render_token, nil)

      widget_ui_event =
        WidgetUiEventEnvelope.new(%{
          type: event_type,
          widget_id: widget_id,
          widget_kind: widget_kind,
          timestamp: timestamp,
          data: data
        })
        |> put_optional(:session_id, session_id)
        |> put_optional(:route_key, route_key)
        |> put_optional(:render_token, render_token)

      dispatch_context =
        %{widget_id: widget_id}
        |> put_optional(:session_id, session_id)
        |> put_optional(:route_key, route_key)
        |> put_optional(:render_token, render_token)

      {:ok,
       %{
         envelope_kind: :widget_ui_event,
         schema_version: @schema_version,
         admitted_at: DateTime.utc_now(),
         widget_ui_event: widget_ui_event,
         dispatch_context: dispatch_context
       }}
    end
  end

  defp normalize_continuity(envelope) do
    with {:ok, correlation_id} <- validate_continuity_id(envelope, :correlation_id),
         {:ok, request_id} <- validate_continuity_id(envelope, :request_id) do
      {:ok, %{correlation_id: correlation_id, request_id: request_id}}
    end
  end

  defp validate_continuity_id(envelope, key) do
    schema_path = "$." <> Atom.to_string(key)

    case get_key(envelope, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        cond do
          byte_size(trimmed) == 0 ->
            {:error,
             validation_error(
               envelope,
               "ingress_continuity_missing",
               "#{key} is required",
               @continuity_stage,
               %{schema_path: schema_path, expected: "non-empty string", received: inspect(value)}
             )}

          Regex.match?(@continuity_id_pattern, trimmed) ->
            {:ok, trimmed}

          true ->
            {:error,
             validation_error(
               envelope,
               "ingress_continuity_invalid",
               "#{key} has invalid format",
               @continuity_stage,
               %{
                 schema_path: schema_path,
                 expected: "id matching #{@continuity_id_pattern.source}",
                 received: inspect(trimmed)
               }
             )}
        end

      invalid ->
        {:error,
         validation_error(
           envelope,
           "ingress_continuity_missing",
           "#{key} is required",
           @continuity_stage,
           %{schema_path: schema_path, expected: "non-empty string", received: inspect(invalid)}
         )}
    end
  end

  defp normalize_auth_context(envelope, continuity_ids) do
    case alias_value(envelope, :auth_context, :auth) do
      nil ->
        {:error,
         validation_error(
           continuity_ids,
           "ingress_auth_missing",
           "Auth context is required",
           @auth_stage,
           %{schema_path: "$.auth_context", expected: "map", received: "nil"}
         )}

      auth_map when is_map(auth_map) ->
        with {:ok, subject_id} <- normalize_auth_subject(auth_map, continuity_ids),
             {:ok, roles} <- normalize_auth_string_list(auth_map, :roles, continuity_ids),
             {:ok, scopes} <- normalize_auth_string_list(auth_map, :scopes, continuity_ids) do
          policy_context = normalize_policy_context(auth_map)
          authenticated = get_boolean(auth_map, :authenticated, true)
          actor_type = optional_string(auth_map, :actor_type, "user")
          tenant_id = optional_string(auth_map, :tenant_id, "default")

          {:ok,
           %{
             subject_id: subject_id,
             actor_type: actor_type,
             tenant_id: tenant_id,
             authenticated: authenticated,
             roles: roles,
             scopes: scopes,
             policy_context: policy_context
           }}
        end

      invalid ->
        {:error,
         validation_error(
           continuity_ids,
           "ingress_auth_invalid",
           "Auth context must be a map",
           @auth_stage,
           %{schema_path: "$.auth_context", expected: "map", received: inspect(invalid)}
         )}
    end
  end

  defp normalize_auth_subject(auth_map, continuity_ids) do
    subject_id = alias_value(auth_map, :subject_id, :actor_id)

    case subject_id do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          {:ok, trimmed}
        else
          {:error,
           validation_error(
             continuity_ids,
             "ingress_auth_invalid",
             "Auth subject is required",
             @auth_stage,
             %{
               schema_path: "$.auth_context.subject_id",
               expected: "non-empty string",
               received: inspect(value)
             }
           )}
        end

      invalid ->
        {:error,
         validation_error(
           continuity_ids,
           "ingress_auth_invalid",
           "Auth subject is required",
           @auth_stage,
           %{
             schema_path: "$.auth_context.subject_id",
             expected: "non-empty string",
             received: inspect(invalid)
           }
         )}
    end
  end

  defp normalize_auth_string_list(auth_map, key, continuity_ids) do
    case get_key(auth_map, key) do
      nil ->
        {:ok, []}

      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1) do
          {:ok, list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}
        else
          {:error,
           validation_error(
             continuity_ids,
             "ingress_auth_invalid",
             "#{key} must be a list of strings",
             @auth_stage,
             %{
               schema_path: "$.auth_context.#{key}",
               expected: "list(string)",
               received: inspect(list)
             }
           )}
        end

      invalid ->
        {:error,
         validation_error(
           continuity_ids,
           "ingress_auth_invalid",
           "#{key} must be a list of strings",
           @auth_stage,
           %{
             schema_path: "$.auth_context.#{key}",
             expected: "list(string)",
             received: inspect(invalid)
           }
         )}
    end
  end

  defp normalize_policy_context(auth_map) do
    policy_context = get_map_or_empty(auth_map, :policy_context)

    policy_version =
      get_key(policy_context, :policy_version) || get_key(auth_map, :policy_version) || "v1"

    feature_flags =
      case get_key(policy_context, :feature_flags) do
        flags when is_map(flags) ->
          flags

        _ ->
          get_map_or_empty(auth_map, :feature_flags)
      end

    policy_context
    |> Map.put(:policy_version, to_string(policy_version))
    |> Map.put(:feature_flags, feature_flags)
  end

  defp get_boolean(map, key, default) do
    case get_key(map, key) do
      value when is_boolean(value) -> value
      _ -> default
    end
  end

  defp get_map_or_empty(map, key) do
    case get_key(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp attach_runtime_context(normalized_payload, continuity_ids, auth_context) do
    dispatch_context =
      normalized_payload.dispatch_context
      |> Map.merge(continuity_ids)
      |> Map.put(:auth_context, auth_context)

    orchestrator_context =
      dispatch_context
      |> Map.put(:envelope_kind, normalized_payload.envelope_kind)
      |> Map.put(:policy_context, auth_context.policy_context)

    {payload_key, payload} =
      case normalized_payload.envelope_kind do
        :ui_command -> {:ui_command, normalized_payload.ui_command}
        :widget_ui_event -> {:widget_ui_event, normalized_payload.widget_ui_event}
      end

    payload_with_continuity =
      payload
      |> Map.put(:correlation_id, continuity_ids.correlation_id)
      |> Map.put(:request_id, continuity_ids.request_id)

    normalized_payload
    |> Map.merge(continuity_ids)
    |> Map.put(:auth_context, auth_context)
    |> Map.put(:dispatch_context, dispatch_context)
    |> Map.put(payload_key, payload_with_continuity)
    |> Map.put(:orchestrator_envelope, %{
      payload: payload_with_continuity,
      context: orchestrator_context
    })
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
    case map do
      value when is_map(value) ->
        cond do
          Map.has_key?(value, key) ->
            Map.get(value, key)

          is_atom(key) and Map.has_key?(value, Atom.to_string(key)) ->
            Map.get(value, Atom.to_string(key))

          true ->
            nil
        end

      _ ->
        nil
    end
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

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp validation_error(source, error_code, message, stage, details, category \\ "ingress") do
    {correlation_id, request_id} = continuity_ids_from(source)

    TypedError.ingress(error_code, message,
      category: category,
      stage: stage,
      retryable: false,
      details: details,
      correlation_id: correlation_id,
      request_id: request_id
    )
  end

  defp continuity_ids_from(source) when is_map(source) do
    correlation_id = get_key(source, :correlation_id)
    request_id = get_key(source, :request_id)
    {normalize_or_default_id(correlation_id, "cor"), normalize_or_default_id(request_id, "req")}
  end

  defp continuity_ids_from(_source), do: {default_id("cor"), default_id("req")}

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

  defp emit_continuity_check(:accepted, normalized_envelope) when is_map(normalized_envelope) do
    Telemetry.emit("ui.ingress.continuity.checked.v1", %{
      outcome: "accepted",
      correlation_id: normalized_envelope.correlation_id,
      request_id: normalized_envelope.request_id,
      envelope_kind: to_string(normalized_envelope.envelope_kind)
    })
  end

  defp emit_continuity_check(:rejected, %TypedError{} = typed_error) do
    if typed_error.stage == @continuity_stage do
      Telemetry.emit("ui.ingress.continuity.checked.v1", %{
        outcome: "rejected",
        error_code: typed_error.error_code,
        correlation_id: typed_error.correlation_id,
        request_id: typed_error.request_id
      })
    end
  end

  defp emit_auth_denied_diagnostics(%TypedError{} = typed_error) do
    if typed_error.stage == @auth_stage do
      Telemetry.emit("ui.ingress.auth.denied.v1", %{
        error_code: typed_error.error_code,
        error_category: typed_error.category,
        error_stage: typed_error.stage,
        correlation_id: typed_error.correlation_id,
        request_id: typed_error.request_id,
        details: typed_error.details
      })
    end
  end

  defp emit_admitted_ingress(normalized_envelope) do
    base_payload = %{
      correlation_id: normalized_envelope.correlation_id,
      request_id: normalized_envelope.request_id,
      envelope_kind: to_string(normalized_envelope.envelope_kind),
      schema_version: normalized_envelope.schema_version
    }

    payload =
      case normalized_envelope.envelope_kind do
        :ui_command ->
          session_id = normalized_envelope |> get_key(:ui_command) |> get_key(:session_id)
          Map.put(base_payload, :session_id, session_id)

        :widget_ui_event ->
          base_payload
      end

    Telemetry.emit("ui.command.received.v1", payload)
  end

  defp emit_denied_ingress(%TypedError{} = typed_error, envelope) do
    policy_context =
      case alias_value(envelope, :auth_context, :auth) do
        auth_map when is_map(auth_map) -> normalize_policy_context(auth_map)
        _ -> %{}
      end

    Telemetry.emit("ui.ingress.denied.v1", %{
      error_code: typed_error.error_code,
      message: typed_error.message,
      category: typed_error.category,
      stage: typed_error.stage,
      error_category: typed_error.category,
      error_stage: typed_error.stage,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id,
      policy_context: policy_context
    })

    Telemetry.emit("ui.ingress.failure.metric.v1", %{
      metric: "ingress_failures_total",
      failure_class: classify_ingress_failure(typed_error),
      error_code: typed_error.error_code,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id
    })
  end

  defp classify_ingress_failure(%TypedError{error_code: error_code}) do
    case error_code do
      "ingress_auth_missing" -> "unauthorized"
      "ingress_auth_invalid" -> "unauthorized"
      _ -> "malformed"
    end
  end

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp alias_value(map, primary_key, fallback_key) when is_map(map) do
    cond do
      has_key?(map, primary_key) ->
        get_key(map, primary_key)

      has_key?(map, fallback_key) ->
        get_key(map, fallback_key)

      true ->
        nil
    end
  end

  defp alias_value(_map, _primary_key, _fallback_key), do: nil
end
