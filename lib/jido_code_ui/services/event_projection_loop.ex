defmodule JidoCodeUi.Services.EventProjectionLoop do
  @moduledoc """
  Projects rendered widget interactions back into ingress envelopes and executes
  the render-event round-trip through substrate admission and orchestration.
  """

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.TypedError

  @schema_version "v1"
  @projection_stage "event_projection"
  @validation_stage "event_projection_validation"

  @type projection_result :: %{
          projected_event: map(),
          admitted_event: map(),
          orchestration: map(),
          continuity: map()
        }

  @spec project_widget_event(map(), map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def project_widget_event(render_result, browser_event, opts \\ [])

  def project_widget_event(render_result, browser_event, opts)
      when is_map(render_result) and is_map(browser_event) and is_list(opts) do
    with {:ok, normalized} <- normalize_projection_inputs(render_result, browser_event, opts) do
      projected_event =
        %{
          type: normalized.event_type,
          widget_id: normalized.widget_id,
          widget_kind: normalized.widget_kind,
          correlation_id: normalized.continuity.correlation_id,
          request_id: normalized.continuity.request_id,
          timestamp: normalized.timestamp,
          session_id: normalized.session_id,
          route_key: normalized.route_key,
          render_token: normalized.render_token,
          data: normalized.event_data,
          auth_context: normalized.auth_context
        }
        |> compact_nil_fields()

      Telemetry.emit("ui.event_projection.projected.v1", %{
        correlation_id: normalized.continuity.correlation_id,
        request_id: normalized.continuity.request_id,
        session_id: normalized.session_id,
        route_key: normalized.route_key,
        render_token: normalized.render_token,
        event_type: normalized.event_type,
        widget_id: normalized.widget_id
      })

      {:ok, projected_event}
    end
  end

  def project_widget_event(render_result, browser_event, opts) when is_list(opts) do
    continuity = projection_continuity(render_result, browser_event, opts)

    {:error,
     projection_error(
       "event_projection_invalid_input",
       "Render result and browser event payloads must be maps",
       continuity,
       %{
         render_result_type: inspect(render_result),
         browser_event_type: inspect(browser_event),
         schema_path: "$"
       }
     )}
  end

  @spec admit_projected_event(map(), map(), keyword()) ::
          {:ok, %{projected_event: map(), admitted_event: map()}} | {:error, TypedError.t()}
  def admit_projected_event(render_result, browser_event, opts \\ [])

  def admit_projected_event(render_result, browser_event, opts)
      when is_map(render_result) and is_map(browser_event) and is_list(opts) do
    with {:ok, projected_event} <- project_widget_event(render_result, browser_event, opts),
         {:ok, admitted_event} <- Substrate.admit(projected_event) do
      Telemetry.emit("ui.event_projection.admitted.v1", %{
        correlation_id: admitted_event.correlation_id,
        request_id: admitted_event.request_id,
        session_id: nested_value(admitted_event, [:dispatch_context, :session_id]),
        envelope_kind: to_string(admitted_event.envelope_kind),
        widget_id: nested_value(admitted_event, [:dispatch_context, :widget_id]),
        route_key: nested_value(admitted_event, [:dispatch_context, :route_key])
      })

      {:ok, %{projected_event: projected_event, admitted_event: admitted_event}}
    end
  end

  def admit_projected_event(render_result, browser_event, opts) when is_list(opts) do
    project_widget_event(render_result, browser_event, opts)
  end

  @spec round_trip(map(), map(), keyword()) ::
          {:ok, projection_result()} | {:error, TypedError.t()}
  def round_trip(render_result, browser_event, opts \\ [])

  def round_trip(render_result, browser_event, opts)
      when is_map(render_result) and is_map(browser_event) and is_list(opts) do
    started_at_us = System.monotonic_time(:microsecond)
    execution_context = Keyword.get(opts, :execution_context, %{})
    continuity = projection_continuity(render_result, browser_event, opts)

    result =
      with {:ok, projected} <- admit_projected_event(render_result, browser_event, opts),
           {:ok, orchestration} <-
             UiOrchestrator.execute(projected.admitted_event, execution_context) do
        {:ok,
         %{
           projected_event: projected.projected_event,
           admitted_event: projected.admitted_event,
           orchestration: orchestration,
           continuity: %{
             correlation_id: orchestration.continuity.correlation_id,
             request_id: orchestration.continuity.request_id,
             session_id: orchestration.continuity.session_id,
             route_key: orchestration.route_key
           }
         }}
      end

    latency_ms = elapsed_ms(started_at_us)
    emit_round_trip_outcome(result, latency_ms, continuity)
    result
  end

  def round_trip(render_result, browser_event, opts) when is_list(opts) do
    continuity = projection_continuity(render_result, browser_event, opts)
    started_at_us = System.monotonic_time(:microsecond)

    error =
      projection_error(
        "event_projection_invalid_input",
        "Render result and browser event payloads must be maps",
        continuity,
        %{
          render_result_type: inspect(render_result),
          browser_event_type: inspect(browser_event),
          schema_path: "$"
        },
        stage: @validation_stage
      )

    latency_ms = elapsed_ms(started_at_us)
    emit_round_trip_outcome({:error, error}, latency_ms, continuity)
    {:error, error}
  end

  defp normalize_projection_inputs(render_result, browser_event, opts) do
    continuity = projection_continuity(render_result, browser_event, opts)
    event_projection = get_map(render_result, :event_projection)
    projection = get_map(render_result, :projection)

    browser_data =
      first_non_empty_map([get_map(browser_event, :data), get_map(browser_event, :payload)])

    with :ok <- validate_render_contract(event_projection, continuity),
         {:ok, event_type} <- require_string(browser_event, :type, "$.type", continuity),
         {:ok, widget_id} <- require_string(browser_event, :widget_id, "$.widget_id", continuity),
         {:ok, auth_context} <-
           resolve_auth_context(render_result, browser_event, opts, continuity),
         {:ok, session_id} <-
           resolve_session_id(event_projection, render_result, browser_data, opts, continuity),
         {:ok, route_key} <-
           resolve_route_key(event_projection, render_result, browser_data, opts, continuity),
         {:ok, render_token} <-
           resolve_render_token(event_projection, render_result, browser_data, opts, continuity) do
      widget_kind =
        normalize_string(get_value(browser_event, :widget_kind)) ||
          widget_kind_from_projection(projection, widget_id) || "unknown_widget"

      event_data =
        browser_data
        |> Map.put_new(:widget_id, widget_id)
        |> Map.put_new(:session_id, session_id)
        |> Map.put_new(:route_key, route_key)
        |> Map.put_new(:render_token, render_token)

      {:ok,
       %{
         event_type: event_type,
         widget_id: widget_id,
         widget_kind: widget_kind,
         event_data: event_data,
         auth_context: auth_context,
         continuity: continuity,
         session_id: session_id,
         route_key: route_key,
         render_token: render_token,
         timestamp: normalize_timestamp(get_value(browser_event, :timestamp))
       }}
    end
  end

  defp validate_render_contract(event_projection, continuity) do
    cond do
      event_projection == %{} ->
        {:error,
         projection_error(
           "event_projection_invalid_render_result",
           "Render result is missing event projection metadata",
           continuity,
           %{
             schema_path: "$.event_projection",
             expected: "map",
             received: inspect(event_projection)
           },
           stage: @validation_stage
         )}

      normalize_string(get_value(event_projection, :schema_version)) != @schema_version ->
        {:error,
         projection_error(
           "event_projection_invalid_render_result",
           "Unsupported event projection schema version",
           continuity,
           %{
             schema_path: "$.event_projection.schema_version",
             expected: @schema_version,
             received: inspect(get_value(event_projection, :schema_version))
           },
           stage: @validation_stage
         )}

      normalize_string(get_value(event_projection, :envelope_type)) != "WidgetUiEventEnvelope" ->
        {:error,
         projection_error(
           "event_projection_invalid_render_result",
           "Unsupported event projection envelope type",
           continuity,
           %{
             schema_path: "$.event_projection.envelope_type",
             expected: "WidgetUiEventEnvelope",
             received: inspect(get_value(event_projection, :envelope_type))
           },
           stage: @validation_stage
         )}

      true ->
        :ok
    end
  end

  defp resolve_auth_context(render_result, browser_event, opts, continuity) do
    auth_context =
      first_non_empty_map([
        Keyword.get(opts, :auth_context),
        get_map(browser_event, :auth_context),
        get_map(render_result, :auth_context)
      ])

    if auth_context == %{} do
      {:error,
       projection_error(
         "event_projection_auth_missing",
         "Auth context is required for event projection admission",
         continuity,
         %{schema_path: "$.auth_context", expected: "map", received: "nil"},
         stage: @validation_stage
       )}
    else
      {:ok, auth_context}
    end
  end

  defp resolve_session_id(event_projection, render_result, browser_data, opts, continuity) do
    render_continuity = get_map(render_result, :continuity)

    session_id =
      normalize_string(Keyword.get(opts, :session_id)) ||
        normalize_string(get_value(event_projection, :session_id)) ||
        normalize_string(get_value(render_continuity, :session_id)) ||
        normalize_string(get_value(browser_data, :session_id))

    if session_id == nil do
      {:error,
       projection_error(
         "event_projection_invalid_event",
         "Event projection requires a session_id",
         continuity,
         %{schema_path: "$.session_id", expected: "non-empty string", received: "nil"},
         stage: @validation_stage
       )}
    else
      {:ok, session_id}
    end
  end

  defp resolve_route_key(event_projection, render_result, browser_data, opts, continuity) do
    render_continuity = get_map(render_result, :continuity)
    render_projection = get_map(render_result, :projection)

    route_key =
      normalize_string(Keyword.get(opts, :route_key)) ||
        normalize_string(get_value(event_projection, :route_key)) ||
        normalize_string(get_value(render_continuity, :route_key)) ||
        normalize_string(get_value(render_projection, :route_key)) ||
        normalize_string(get_value(browser_data, :route_key))

    if route_key == nil do
      {:error,
       projection_error(
         "event_projection_invalid_render_result",
         "Event projection requires a route_key",
         continuity,
         %{schema_path: "$.route_key", expected: "non-empty string", received: "nil"},
         stage: @validation_stage
       )}
    else
      {:ok, route_key}
    end
  end

  defp resolve_render_token(event_projection, render_result, browser_data, opts, continuity) do
    render_continuity = get_map(render_result, :continuity)

    render_token =
      normalize_string(Keyword.get(opts, :render_token)) ||
        normalize_string(get_value(event_projection, :render_token)) ||
        normalize_string(get_value(render_continuity, :render_token)) ||
        normalize_string(get_value(browser_data, :render_token))

    if render_token == nil do
      {:error,
       projection_error(
         "event_projection_invalid_render_result",
         "Event projection requires a render_token",
         continuity,
         %{schema_path: "$.render_token", expected: "non-empty string", received: "nil"},
         stage: @validation_stage
       )}
    else
      {:ok, render_token}
    end
  end

  defp require_string(map, key, schema_path, continuity) do
    case normalize_string(get_value(map, key)) do
      nil ->
        {:error,
         projection_error(
           "event_projection_invalid_event",
           "Projected browser event is missing required field",
           continuity,
           %{
             schema_path: schema_path,
             expected: "non-empty string",
             received: inspect(get_value(map, key))
           },
           stage: @validation_stage
         )}

      value ->
        {:ok, value}
    end
  end

  defp widget_kind_from_projection(projection, widget_id) do
    projection
    |> get_value(:widgets)
    |> case do
      widgets when is_list(widgets) ->
        widgets
        |> Enum.find(fn widget ->
          normalize_string(get_value(widget, :widget_id)) == widget_id
        end)
        |> case do
          nil -> nil
          widget -> normalize_string(get_value(widget, :widget_kind))
        end

      _ ->
        nil
    end
  end

  defp projection_continuity(render_result, browser_event, opts) do
    render_continuity = get_map(render_result, :continuity)

    %{
      correlation_id:
        normalize_string(Keyword.get(opts, :correlation_id)) ||
          normalize_string(get_value(browser_event, :correlation_id)) ||
          normalize_string(get_value(render_continuity, :correlation_id)) ||
          default_id("cor"),
      request_id:
        normalize_string(Keyword.get(opts, :request_id)) ||
          normalize_string(get_value(browser_event, :request_id)) ||
          normalize_string(get_value(render_continuity, :request_id)) ||
          default_id("req")
    }
  end

  defp emit_round_trip_outcome({:ok, result}, latency_ms, continuity) do
    route_key = nested_value(result, [:continuity, :route_key]) || "route-unset"
    session_id = nested_value(result, [:continuity, :session_id])

    Telemetry.emit("ui.render.event.round_trip.v1", %{
      outcome: "success",
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id,
      route_key: route_key,
      session_id: session_id
    })

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_event_round_trip_latency_ms",
      value: latency_ms,
      outcome: "success",
      route_key: route_key,
      session_id: session_id,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_round_trip_outcome({:error, %TypedError{} = typed_error}, latency_ms, continuity) do
    Telemetry.emit("ui.render.event.round_trip.v1", %{
      outcome: "failure",
      error_code: typed_error.error_code,
      error_category: typed_error.category,
      error_stage: typed_error.stage,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id,
      route_key: get_value(typed_error.details, :route_key) || "route-unset"
    })

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_event_round_trip_latency_ms",
      value: latency_ms,
      outcome: "failure",
      error_code: typed_error.error_code,
      error_category: typed_error.category,
      correlation_id: typed_error.correlation_id || continuity.correlation_id,
      request_id: typed_error.request_id || continuity.request_id
    })
  end

  defp projection_error(error_code, message, continuity, details, opts \\ []) do
    TypedError.ingress(error_code, message,
      category: "projection",
      stage: Keyword.get(opts, :stage, @projection_stage),
      details: details,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    )
  end

  defp compact_nil_fields(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp compact_nil_fields(value), do: value

  defp first_non_empty_map(values) when is_list(values) do
    Enum.find(values, %{}, fn value -> is_map(value) and value != %{} end)
  end

  defp normalize_timestamp(nil) do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp normalize_timestamp(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: normalize_timestamp(nil), else: trimmed
  end

  defp normalize_timestamp(_value), do: normalize_timestamp(nil)

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

  defp get_value(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        nil
    end
  end

  defp get_value(_map, _key), do: nil

  defp get_map(map, key) when is_map(map) do
    case get_value(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp get_map(_map, _key), do: %{}

  defp nested_value(value, []), do: value

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> get_value(key)
    |> nested_value(rest)
  end

  defp nested_value(_value, _path), do: nil

  defp elapsed_ms(started_at_us) do
    (System.monotonic_time(:microsecond) - started_at_us) / 1_000
  end

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
