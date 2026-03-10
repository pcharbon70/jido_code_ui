defmodule JidoCodeUi.Services.IurRenderer do
  @moduledoc """
  Deterministic IUR renderer for web-ui projection payloads.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :iur_renderer
  @iur_version "v1"
  @validation_stage "iur_render_validation"
  @adapter_stage "iur_render_adapter"
  @timeout_stage "iur_render_timeout"
  @render_stage "iur_render"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec render(map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def render(render_request, opts \\ [])

  def render(render_request, opts) when is_map(render_request) and is_list(opts) do
    with :ok <- StartupGuard.ensure_ready("iur_render", %{operation: "render"}) do
      continuity = continuity_ids(render_request, opts)
      route_key = normalize_string(get_value(render_request, :route_key)) || "route-unset"
      started_at_us = System.monotonic_time(:microsecond)

      emit_render_started(continuity, route_key)

      result = run_render_pipeline(render_request, continuity, route_key)
      latency_ms = elapsed_ms(started_at_us)

      case result do
        {:ok, render_result} ->
          emit_render_completed(render_result, continuity, route_key)
          emit_render_metrics({:ok, render_result}, continuity, route_key, latency_ms)
          {:ok, render_result}

        {:error, %TypedError{} = typed_error} ->
          emit_render_failure(typed_error, continuity, route_key)
          emit_render_metrics({:error, typed_error}, continuity, route_key, latency_ms)
          {:error, typed_error}
      end
    end
  end

  def render(_render_request, opts) when is_list(opts) do
    continuity = normalize_continuity(opts)
    route_key = "route-unset"
    started_at_us = System.monotonic_time(:microsecond)

    emit_render_started(continuity, route_key)

    typed_error =
      render_error("iur_invalid_render_request", "Render request must be a map", continuity,
        stage: @validation_stage,
        details: %{schema_path: "$", expected: "map", received: "non-map"}
      )

    emit_render_failure(typed_error, continuity, route_key)
    emit_render_metrics({:error, typed_error}, continuity, route_key, elapsed_ms(started_at_us))
    {:error, typed_error}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp run_render_pipeline(render_request, continuity, route_key) do
    cond do
      force_render_timeout?(render_request) ->
        {:error,
         render_error("iur_render_timeout", "IUR render timed out", continuity,
           stage: @timeout_stage,
           details: %{reason: "forced_timeout"}
         )}

      force_render_failure?(render_request) ->
        {:error,
         render_error("iur_adapter_failed", "IUR renderer adapter failed", continuity,
           stage: @adapter_stage,
           details: %{reason: "forced_adapter_failure"}
         )}

      true ->
        with {:ok, normalized} <- normalize_render_request(render_request, continuity, route_key),
             {:ok, projection} <- project_to_web_ui(normalized, continuity) do
          {:ok, build_render_result(projection, normalized, continuity)}
        end
    end
  end

  defp normalize_render_request(render_request, continuity, route_key) do
    compile_result = get_map(render_request, :compile_result)

    iur_document =
      first_non_empty_map([
        get_map(compile_result, :iur_document),
        get_map(render_request, :iur_document),
        get_map(render_request, :iur)
      ])

    iur_version =
      normalize_string(get_value(compile_result, :iur_version)) ||
        normalize_string(get_value(render_request, :iur_version)) || @iur_version

    session_snapshot = get_map(render_request, :session_snapshot)
    session_id = normalize_string(get_value(session_snapshot, :session_id))

    iur_hash =
      normalize_string(get_value(compile_result, :iur_hash)) || hash_iur_document(iur_document)

    root = get_map(iur_document, :root)

    cond do
      iur_document == %{} ->
        {:error,
         invalid_render_input(
           "Missing IUR document payload",
           continuity,
           %{
             schema_path: "$.compile_result.iur_document",
             expected: "map",
             received: inspect(iur_document)
           }
         )}

      root == %{} ->
        {:error,
         invalid_render_input(
           "IUR root node is required",
           continuity,
           %{
             schema_path: "$.compile_result.iur_document.root",
             expected: "map",
             received: inspect(get_value(iur_document, :root))
           }
         )}

      iur_version != @iur_version ->
        {:error,
         invalid_render_input(
           "Unsupported IUR document version",
           continuity,
           %{
             schema_path: "$.compile_result.iur_version",
             expected: @iur_version,
             received: iur_version
           }
         )}

      normalize_string(get_value(root, :type)) == nil ->
        {:error,
         invalid_render_input(
           "IUR root node type is required",
           continuity,
           %{
             schema_path: "$.compile_result.iur_document.root.type",
             expected: "non-empty string",
             received: inspect(get_value(root, :type))
           }
         )}

      true ->
        {:ok,
         %{
           compile_result: compile_result,
           iur_document: iur_document,
           iur_version: iur_version,
           iur_hash: iur_hash,
           root: root,
           session_id: session_id,
           route_key: route_key,
           session_snapshot: session_snapshot
         }}
    end
  end

  defp project_to_web_ui(normalized, continuity) do
    try do
      projected_root = project_node(normalized.root, normalized.route_key, "0")
      widget_index = flatten_widget_index(projected_root)
      render_token = render_token(normalized.iur_hash, continuity.correlation_id)

      projection = %{
        schema_version: "v1",
        route_key: normalized.route_key,
        iur_version: normalized.iur_version,
        iur_hash: normalized.iur_hash,
        root: projected_root,
        widgets: widget_index
      }

      {:ok, %{projection: projection, render_token: render_token}}
    rescue
      error ->
        {:error,
         render_error("iur_adapter_failed", "Failed to project IUR to web-ui payload", continuity,
           stage: @adapter_stage,
           details: %{reason: Exception.message(error)}
         )}
    end
  end

  defp build_render_result(projected, normalized, continuity) do
    event_projection = %{
      envelope_type: "WidgetUiEventEnvelope",
      schema_version: "v1",
      session_id: normalized.session_id,
      route_key: normalized.route_key,
      correlation_id: continuity.correlation_id,
      render_token: projected.render_token
    }

    %{
      rendered: true,
      projection: projected.projection,
      continuity: %{
        correlation_id: continuity.correlation_id,
        request_id: continuity.request_id,
        session_id: normalized.session_id,
        route_key: normalized.route_key,
        render_token: projected.render_token
      },
      event_projection: event_projection,
      render_metadata: %{
        payload_class: payload_class(normalized.root),
        iur_version: normalized.iur_version,
        iur_hash: normalized.iur_hash
      }
    }
  end

  defp project_node(node, route_key, path) when is_map(node) do
    widget_kind = normalize_string(get_value(node, :type)) || "unknown.widget"
    widget_id = deterministic_widget_id(route_key, path, widget_kind)

    children =
      node
      |> get_value(:children)
      |> case do
        values when is_list(values) ->
          values
          |> Enum.with_index()
          |> Enum.map(fn {child, index} ->
            project_node(child, route_key, path <> "." <> Integer.to_string(index))
          end)

        _ ->
          []
      end

    %{
      widget_id: widget_id,
      widget_kind: widget_kind,
      props: canonical_map(get_map(node, :props)),
      attrs: canonical_map(get_map(node, :attrs)),
      children: children
    }
  end

  defp project_node(_node, route_key, path) do
    %{
      widget_id: deterministic_widget_id(route_key, path, "unknown.widget"),
      widget_kind: "unknown.widget",
      props: %{},
      attrs: %{},
      children: []
    }
  end

  defp flatten_widget_index(projected_root) do
    flatten_widget_index(projected_root, [])
  end

  defp flatten_widget_index(%{widget_id: widget_id} = node, acc) do
    current = %{
      widget_id: widget_id,
      widget_kind: node.widget_kind
    }

    node.children
    |> Enum.reduce(acc ++ [current], fn child, acc_widgets ->
      flatten_widget_index(child, acc_widgets)
    end)
  end

  defp flatten_widget_index(_node, acc), do: acc

  defp deterministic_widget_id(route_key, path, widget_kind) do
    digest = :erlang.phash2({route_key, path, widget_kind}, 1_000_000_000)
    "wid-" <> Integer.to_string(digest)
  end

  defp render_token(iur_hash, correlation_id) do
    token_digest = :erlang.phash2({iur_hash, correlation_id}, 1_000_000_000)
    "rnd-" <> Integer.to_string(token_digest)
  end

  defp emit_render_started(continuity, route_key) do
    Telemetry.emit("ui.iur.render.started.v1", %{
      route_key: route_key,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_render_completed(render_result, continuity, route_key) do
    Telemetry.emit("ui.iur.render.completed.v1", %{
      route_key: route_key,
      payload_class: payload_class_from_result(render_result),
      iur_version: nested_value(render_result, [:render_metadata, :iur_version]),
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_render_failure(%TypedError{} = typed_error, continuity, route_key) do
    Telemetry.emit("ui.iur.render.failed.v1", %{
      route_key: route_key,
      error_code: typed_error.error_code,
      error_category: typed_error.category,
      error_stage: typed_error.stage,
      error_classification: classify_render_error(typed_error.error_code),
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_render_metrics({:ok, render_result}, continuity, route_key, latency_ms) do
    payload_class = payload_class_from_result(render_result)

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_latency_ms",
      value: latency_ms,
      outcome: "success",
      route_key: route_key,
      payload_class: payload_class,
      error_category: "none",
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_total",
      value: 1,
      outcome: "success",
      route_key: route_key,
      payload_class: payload_class,
      error_category: "none",
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_render_metrics(
         {:error, %TypedError{} = typed_error},
         continuity,
         route_key,
         latency_ms
       ) do
    classification = classify_render_error(typed_error.error_code)

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_latency_ms",
      value: latency_ms,
      outcome: "failure",
      route_key: route_key,
      payload_class: "unknown",
      error_category: typed_error.category,
      error_code: typed_error.error_code,
      error_classification: classification,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    Telemetry.emit("ui.iur.render.metric.v1", %{
      metric: "render_total",
      value: 1,
      outcome: "failure",
      route_key: route_key,
      payload_class: "unknown",
      error_category: typed_error.category,
      error_code: typed_error.error_code,
      error_classification: classification,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp payload_class_from_result(render_result) do
    normalize_string(nested_value(render_result, [:render_metadata, :payload_class])) ||
      payload_class(nested_value(render_result, [:projection, :root]))
  end

  defp classify_render_error("iur_invalid_document"), do: "invalid_iur"
  defp classify_render_error("iur_adapter_failed"), do: "adapter_failure"
  defp classify_render_error("iur_render_timeout"), do: "timeout"
  defp classify_render_error(_error_code), do: "render_failure"

  defp invalid_render_input(message, continuity, details) do
    render_error("iur_invalid_document", message, continuity,
      stage: @validation_stage,
      details: details
    )
  end

  defp render_error(error_code, message, continuity, opts) do
    TypedError.ingress(error_code, message,
      category: "render",
      stage: Keyword.get(opts, :stage, @render_stage),
      details: Keyword.get(opts, :details, %{}),
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    )
  end

  defp payload_class(root) do
    node_count = count_nodes(root)

    cond do
      node_count <= 0 -> "unknown"
      node_count <= 5 -> "small"
      node_count <= 25 -> "medium"
      true -> "large"
    end
  end

  defp count_nodes(node) when is_map(node) do
    children =
      case get_value(node, :children) do
        values when is_list(values) -> values
        _ -> []
      end

    1 + Enum.reduce(children, 0, fn child, acc -> acc + count_nodes(child) end)
  end

  defp count_nodes(_node), do: 0

  defp force_render_failure?(render_request) do
    get_value(render_request, :force_error) == true or
      nested_value(render_request, [
        :compile_result,
        :dsl_document,
        :command,
        :payload,
        :force_render_error
      ]) == true or
      nested_value(render_request, [
        :compile_result,
        :dsl_document,
        :root,
        :props,
        :force_render_error
      ]) == true
  end

  defp force_render_timeout?(render_request) do
    get_value(render_request, :force_timeout) == true or
      nested_value(render_request, [
        :compile_result,
        :dsl_document,
        :command,
        :payload,
        :force_render_timeout
      ]) == true
  end

  defp continuity_ids(render_request, opts) do
    %{
      correlation_id:
        normalize_string(Keyword.get(opts, :correlation_id)) ||
          normalize_string(get_value(render_request, :correlation_id)) ||
          default_id("cor"),
      request_id:
        normalize_string(Keyword.get(opts, :request_id)) ||
          normalize_string(get_value(render_request, :request_id)) ||
          default_id("req")
    }
  end

  defp normalize_continuity(%{correlation_id: correlation_id, request_id: request_id}) do
    %{
      correlation_id: normalize_string(correlation_id) || default_id("cor"),
      request_id: normalize_string(request_id) || default_id("req")
    }
  end

  defp normalize_continuity(opts) when is_list(opts) do
    %{
      correlation_id: normalize_string(Keyword.get(opts, :correlation_id)) || default_id("cor"),
      request_id: normalize_string(Keyword.get(opts, :request_id)) || default_id("req")
    }
  end

  defp normalize_continuity(_value) do
    %{correlation_id: default_id("cor"), request_id: default_id("req")}
  end

  defp canonical_map(map) when is_map(map) do
    map
    |> map_for_enumeration()
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
  end

  defp canonical_map(_map), do: %{}

  defp canonical_value(value) when is_map(value), do: canonical_map(value)
  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)
  defp canonical_value(value), do: value

  defp map_for_enumeration(%_{} = struct), do: Map.from_struct(struct)
  defp map_for_enumeration(map), do: map

  defp hash_iur_document(iur_document) when is_map(iur_document) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(iur_document))
    |> Base.encode16(case: :lower)
  end

  defp hash_iur_document(_iur_document), do: nil

  defp first_non_empty_map(maps) when is_list(maps) do
    Enum.find(maps, %{}, fn map -> is_map(map) and map != %{} end)
  end

  defp normalize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_value), do: nil

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
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
