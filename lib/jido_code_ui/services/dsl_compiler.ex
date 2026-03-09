defmodule JidoCodeUi.Services.DslCompiler do
  @moduledoc """
  Server-authoritative DSL compiler with schema validation and compatibility
  checks.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :dsl_compiler
  @supported_dsl_versions MapSet.new(["v1"])
  @validation_stage "dsl_validation"
  @compile_stage "dsl_compile"
  @iur_version "v1"
  @parity_table :jido_code_ui_compile_parity

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec compile(map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def compile(compile_request, opts \\ [])

  def compile(compile_request, opts) when is_map(compile_request) and is_list(opts) do
    with :ok <- StartupGuard.ensure_ready("dsl_compile", %{operation: "compile"}) do
      continuity = continuity_ids(compile_request, opts)
      route_key = normalize_string(get_value(compile_request, :route_key)) || "route-unset"
      preview_dsl_version = preview_dsl_version(compile_request, continuity)

      emit_compile_started(continuity, route_key, preview_dsl_version)

      started_at_us = System.monotonic_time(:microsecond)
      result = run_compile_pipeline(compile_request, opts, continuity)
      latency_ms = elapsed_ms(started_at_us)

      emit_compile_outcome(result, continuity, route_key, preview_dsl_version, latency_ms)

      result
    end
  end

  def compile(_compile_request, opts) when is_list(opts) do
    continuity = normalize_continuity(opts)
    route_key = "route-unset"
    preview_dsl_version = "unknown"
    started_at_us = System.monotonic_time(:microsecond)

    emit_compile_started(continuity, route_key, preview_dsl_version)

    error =
      compile_error("dsl_compile_invalid_request", "Compile request must be a map", opts,
        stage: @validation_stage,
        details: %{schema_path: "$", expected: "map", received: "non-map"}
      )

    latency_ms = elapsed_ms(started_at_us)
    emit_compile_outcome({:error, error}, continuity, route_key, preview_dsl_version, latency_ms)

    {:error, error}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp run_compile_pipeline(compile_request, opts, continuity) do
    if force_compile_failure?(compile_request) do
      {:error,
       compile_error("dsl_compile_failed", "DSL compile failed", continuity,
         details: %{reason: "forced_failure"}
       )}
    else
      with {:ok, normalized} <- normalize_compile_request(compile_request, opts),
           :ok <- validate_dsl_document(normalized.dsl_document, normalized.continuity),
           :ok <-
             validate_custom_nodes(
               normalized.dsl_document,
               normalized.feature_flags,
               normalized.continuity
             ) do
        custom_nodes = extract_custom_nodes(normalized.dsl_document)
        iur_document = build_iur_document(normalized)
        iur_hash = hash_iur_document(iur_document)
        diagnostics = compile_diagnostics(normalized, custom_nodes)

        {:ok,
         %{
           compile_authority: "server",
           dsl_version: normalized.dsl_version,
           iur_version: @iur_version,
           iur_document: iur_document,
           iur_hash: iur_hash,
           diagnostics: diagnostics,
           dsl_document: normalized.dsl_document,
           compile_opts: opts
         }}
      end
    end
  end

  defp normalize_compile_request(compile_request, opts) do
    continuity = continuity_ids(compile_request, opts)
    feature_flags = resolve_feature_flags(compile_request, opts)

    with {:ok, dsl_document} <- extract_dsl_document(compile_request, continuity),
         {:ok, dsl_version} <- normalize_dsl_version(dsl_document, continuity) do
      {:ok,
       %{
         dsl_document: dsl_document,
         dsl_version: dsl_version,
         policy_version: resolve_policy_version(compile_request, opts),
         feature_flags: feature_flags,
         continuity: continuity
       }}
    end
  end

  defp extract_dsl_document(compile_request, continuity) do
    cond do
      is_map(get_map(compile_request, :dsl_document)) and
          get_map(compile_request, :dsl_document) != %{} ->
        {:ok, get_map(compile_request, :dsl_document)}

      is_map(get_map(compile_request, :unified_ui_dsl_document)) and
          get_map(compile_request, :unified_ui_dsl_document) != %{} ->
        {:ok, get_map(compile_request, :unified_ui_dsl_document)}

      is_map(get_map(compile_request, :command)) and
          is_map(get_map(get_map(compile_request, :command), :payload)) ->
        payload = get_map(get_map(compile_request, :command), :payload)
        {:ok, legacy_dsl_document(payload)}

      dsl_document_shape?(compile_request) ->
        {:ok, compile_request}

      true ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "Missing DSL document payload",
           continuity,
           %{
             schema_path: "$.dsl_document",
             expected: "UnifiedUiDslDocument map",
             received_keys: compile_request |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
           }
         )}
    end
  end

  defp legacy_dsl_document(payload) do
    %{
      dsl_version: "v1",
      root: %{
        type: "legacy.command",
        props: payload
      },
      metadata: %{
        compatibility_mode: "legacy_command_payload"
      }
    }
  end

  defp normalize_dsl_version(dsl_document, continuity) do
    version =
      dsl_document
      |> get_value(:dsl_version)
      |> normalize_string()

    cond do
      version == nil ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "DSL document is missing dsl_version",
           continuity,
           %{
             schema_path: "$.dsl_version",
             expected: "non-empty string",
             received: inspect(get_value(dsl_document, :dsl_version))
           }
         )}

      not MapSet.member?(@supported_dsl_versions, version) ->
        {:error,
         validation_error(
           "dsl_schema_incompatible",
           "Unsupported DSL schema version",
           continuity,
           %{
             schema_path: "$.dsl_version",
             expected: "one of #{Enum.join(MapSet.to_list(@supported_dsl_versions), ", ")}",
             received: version,
             supported_versions: Enum.sort(MapSet.to_list(@supported_dsl_versions))
           }
         )}

      true ->
        {:ok, version}
    end
  end

  defp validate_dsl_document(dsl_document, continuity) do
    root = get_map(dsl_document, :root)

    cond do
      root == %{} ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "DSL document is missing root node",
           continuity,
           %{
             schema_path: "$.root",
             expected: "map",
             received: inspect(get_value(dsl_document, :root))
           }
         )}

      true ->
        validate_node(root, "$.root", continuity)
    end
  end

  defp validate_node(node, path, continuity) when is_map(node) do
    with :ok <- validate_required_string(node, :type, path <> ".type", continuity),
         :ok <- validate_optional_map(node, :props, path <> ".props", continuity),
         :ok <- validate_optional_map(node, :attrs, path <> ".attrs", continuity),
         :ok <- validate_optional_custom_node_type(node, path, continuity),
         :ok <- validate_optional_children(node, path <> ".children", continuity) do
      :ok
    end
  end

  defp validate_node(node, path, continuity) do
    {:error,
     validation_error(
       "dsl_schema_invalid",
       "DSL node must be a map",
       continuity,
       %{schema_path: path, expected: "map", received: inspect(node)}
     )}
  end

  defp validate_required_string(map, key, path, continuity) do
    case normalize_string(get_value(map, key)) do
      nil ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "Required DSL field is missing",
           continuity,
           %{
             schema_path: path,
             expected: "non-empty string",
             received: inspect(get_value(map, key))
           }
         )}

      _value ->
        :ok
    end
  end

  defp validate_optional_map(map, key, path, continuity) do
    case get_value(map, key) do
      nil ->
        :ok

      value when is_map(value) ->
        :ok

      invalid ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "Optional DSL field must be a map",
           continuity,
           %{schema_path: path, expected: "map", received: inspect(invalid)}
         )}
    end
  end

  defp validate_optional_children(map, path, continuity) do
    case get_value(map, :children) do
      nil ->
        :ok

      children when is_list(children) ->
        Enum.with_index(children)
        |> Enum.reduce_while(:ok, fn {child, index}, :ok ->
          child_path = path <> "[#{index}]"

          case validate_node(child, child_path, continuity) do
            :ok -> {:cont, :ok}
            {:error, _reason} = error -> {:halt, error}
          end
        end)

      invalid ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "Node children must be a list",
           continuity,
           %{schema_path: path, expected: "list(map)", received: inspect(invalid)}
         )}
    end
  end

  defp validate_optional_custom_node_type(map, path, continuity) do
    case get_value(map, :custom_node_type) do
      nil ->
        :ok

      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error,
           validation_error(
             "dsl_schema_invalid",
             "custom_node_type cannot be empty",
             continuity,
             %{
               schema_path: path <> ".custom_node_type",
               expected: "non-empty string",
               received: inspect(value)
             }
           )}
        else
          :ok
        end

      invalid ->
        {:error,
         validation_error(
           "dsl_schema_invalid",
           "custom_node_type must be a string",
           continuity,
           %{
             schema_path: path <> ".custom_node_type",
             expected: "string",
             received: inspect(invalid)
           }
         )}
    end
  end

  defp validate_custom_nodes(dsl_document, feature_flags, continuity) do
    custom_nodes = extract_custom_nodes(dsl_document)

    if custom_nodes == [] do
      :ok
    else
      with :ok <- ensure_custom_nodes_enabled(custom_nodes, feature_flags, continuity),
           :ok <- ensure_custom_nodes_allowlisted(custom_nodes, feature_flags, continuity) do
        :ok
      end
    end
  end

  defp ensure_custom_nodes_enabled(custom_nodes, feature_flags, continuity) do
    enabled =
      case get_value(feature_flags, :custom_dsl_nodes) do
        true -> true
        "true" -> true
        1 -> true
        _ -> false
      end

    if enabled do
      :ok
    else
      {:error,
       validation_error(
         "dsl_custom_node_disallowed",
         "Custom DSL node compilation is disabled",
         continuity,
         %{
           schema_path: "$.root",
           custom_nodes: custom_nodes,
           feature_flag: "custom_dsl_nodes"
         }
       )}
    end
  end

  defp ensure_custom_nodes_allowlisted(custom_nodes, feature_flags, continuity) do
    allowlist =
      feature_flags
      |> get_value(:custom_node_allowlist)
      |> normalize_string_list()
      |> MapSet.new()

    allowed? =
      MapSet.size(allowlist) == 0 or
        Enum.all?(custom_nodes, &MapSet.member?(allowlist, &1))

    if allowed? do
      :ok
    else
      {:error,
       validation_error(
         "dsl_custom_node_incompatible",
         "Custom DSL nodes are not in the policy allowlist",
         continuity,
         %{
           schema_path: "$.root",
           custom_nodes: custom_nodes,
           custom_node_allowlist: Enum.sort(MapSet.to_list(allowlist))
         }
       )}
    end
  end

  defp extract_custom_nodes(dsl_document) do
    from_document =
      dsl_document
      |> get_value(:custom_nodes)
      |> normalize_string_list()

    from_legacy_payload =
      dsl_document
      |> get_map(:root)
      |> get_map(:props)
      |> get_value(:custom_nodes)
      |> normalize_string_list()

    from_tree =
      dsl_document
      |> get_map(:root)
      |> collect_tree_custom_nodes()

    (from_document ++ from_legacy_payload ++ from_tree)
    |> Enum.uniq()
  end

  defp collect_tree_custom_nodes(node) when is_map(node) do
    from_custom_node_type =
      case get_value(node, :custom_node_type) do
        value when is_binary(value) ->
          normalized = String.trim(value)
          if normalized == "", do: [], else: [normalized]

        _ ->
          []
      end

    from_type =
      case normalize_string(get_value(node, :type)) do
        "custom." <> custom_type -> [custom_type]
        _ -> []
      end

    from_children =
      node
      |> get_value(:children)
      |> case do
        children when is_list(children) -> Enum.flat_map(children, &collect_tree_custom_nodes/1)
        _ -> []
      end

    from_custom_node_type ++ from_type ++ from_children
  end

  defp collect_tree_custom_nodes(_node), do: []

  defp build_iur_document(normalized) do
    root = normalized.dsl_document |> get_map(:root) |> canonical_iur_node()

    %{
      "iur_version" => @iur_version,
      "dsl_version" => normalized.dsl_version,
      "root" => root,
      "metadata" =>
        canonical_map(%{
          compile_authority: "server",
          policy_version: normalized.policy_version
        })
    }
    |> canonical_map()
  end

  defp canonical_iur_node(node) when is_map(node) do
    type = normalize_string(get_value(node, :type))

    children =
      node
      |> get_value(:children)
      |> case do
        list when is_list(list) -> Enum.map(list, &canonical_iur_node/1)
        _ -> []
      end

    base =
      %{
        "type" => type,
        "props" => node |> get_map(:props) |> canonical_map(),
        "attrs" => node |> get_map(:attrs) |> canonical_map(),
        "children" => children
      }
      |> canonical_map()

    case normalize_string(get_value(node, :custom_node_type)) || custom_type_from_node_type(type) do
      nil -> base
      custom_node_type -> Map.put(base, "custom_node_type", custom_node_type)
    end
  end

  defp canonical_iur_node(_node) do
    %{
      "type" => "invalid.node",
      "props" => %{},
      "attrs" => %{},
      "children" => []
    }
  end

  defp custom_type_from_node_type("custom." <> custom_type), do: custom_type
  defp custom_type_from_node_type(_type), do: nil

  defp canonical_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
  end

  defp canonical_map(_map), do: %{}

  defp canonical_value(value) when is_map(value), do: canonical_map(value)
  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)
  defp canonical_value(value), do: value

  defp hash_iur_document(iur_document) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(iur_document))
    |> Base.encode16(case: :lower)
  end

  defp compile_diagnostics(normalized, custom_nodes) do
    compatibility_mode =
      normalized.dsl_document
      |> get_map(:metadata)
      |> get_value(:compatibility_mode)
      |> normalize_string()

    compatibility_diagnostics =
      if compatibility_mode == "legacy_command_payload" do
        [
          %{
            code: "dsl_compat_legacy_payload",
            severity: "warning",
            path: "$",
            message: "Compile request used compatibility-mode legacy command payload"
          }
        ]
      else
        []
      end

    custom_node_diagnostics =
      if custom_nodes == [] do
        []
      else
        [
          %{
            code: "dsl_custom_nodes_compiled",
            severity: "info",
            path: "$.root",
            message: "Custom DSL nodes compiled successfully",
            custom_nodes: Enum.sort(custom_nodes)
          }
        ]
      end

    (compatibility_diagnostics ++ custom_node_diagnostics)
    |> Enum.map(&canonical_map/1)
    |> sort_diagnostics()
  end

  defp sort_diagnostics(diagnostics) do
    Enum.sort_by(diagnostics, fn diagnostic ->
      {
        severity_rank(Map.get(diagnostic, "severity")),
        Map.get(diagnostic, "code", ""),
        Map.get(diagnostic, "path", ""),
        Map.get(diagnostic, "message", "")
      }
    end)
  end

  defp severity_rank("error"), do: 0
  defp severity_rank("warning"), do: 1
  defp severity_rank("info"), do: 2
  defp severity_rank("debug"), do: 3
  defp severity_rank(_other), do: 4

  defp emit_compile_started(continuity, route_key, dsl_version) do
    Telemetry.emit("ui.dsl.compile.started.v1", %{
      route_key: route_key,
      dsl_version: dsl_version,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_compile_outcome(
         {:ok, compile_result},
         continuity,
         route_key,
         preview_dsl_version,
         latency_ms
       ) do
    dsl_version = compile_result.dsl_version || preview_dsl_version
    complexity_class = complexity_class(compile_result.iur_document)

    Telemetry.emit("ui.dsl.compile.completed.v1", %{
      route_key: route_key,
      dsl_version: dsl_version,
      iur_version: compile_result.iur_version,
      iur_hash: compile_result.iur_hash,
      compile_authority: compile_result.compile_authority,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    emit_compile_metrics(
      continuity,
      route_key,
      dsl_version,
      complexity_class,
      "success",
      "none",
      nil,
      latency_ms
    )

    emit_parity_diagnostic(compile_result, continuity, route_key)
  end

  defp emit_compile_outcome(
         {:error, %TypedError{} = typed_error},
         continuity,
         route_key,
         preview_dsl_version,
         latency_ms
       ) do
    dsl_version =
      typed_error.details
      |> get_value(:dsl_version)
      |> normalize_string() || preview_dsl_version

    Telemetry.emit("ui.dsl.compile.failed.v1", %{
      route_key: route_key,
      dsl_version: dsl_version,
      error_code: typed_error.error_code,
      error_category: typed_error.category,
      error_stage: typed_error.stage,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    emit_compile_metrics(
      continuity,
      route_key,
      dsl_version,
      "unknown",
      "failure",
      typed_error.category,
      typed_error.error_code,
      latency_ms
    )
  end

  defp emit_compile_metrics(
         continuity,
         route_key,
         dsl_version,
         complexity_class,
         outcome,
         error_category,
         error_code,
         latency_ms
       ) do
    Telemetry.emit("ui.dsl.compile.metric.v1", %{
      metric: "compile_latency_ms",
      value: latency_ms,
      route_key: route_key,
      dsl_version: dsl_version,
      complexity_class: complexity_class,
      outcome: outcome,
      error_category: error_category,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    Telemetry.emit("ui.dsl.compile.metric.v1", %{
      metric: "compile_total",
      value: 1,
      route_key: route_key,
      dsl_version: dsl_version,
      complexity_class: complexity_class,
      outcome: outcome,
      error_category: error_category,
      error_code: error_code,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp emit_parity_diagnostic(compile_result, continuity, route_key) do
    table = ensure_parity_table!()

    signature =
      compile_result.iur_document
      |> signature_payload(compile_result.dsl_version)
      |> hash_iur_document()

    previous_hash =
      case :ets.lookup(table, signature) do
        [{^signature, hash}] when is_binary(hash) -> hash
        _ -> nil
      end

    status =
      cond do
        previous_hash == nil -> "baseline"
        previous_hash == compile_result.iur_hash -> "match"
        true -> "mismatch"
      end

    :ets.insert(table, {signature, compile_result.iur_hash})

    Telemetry.emit("ui.dsl.compile.determinism.parity.v1", %{
      route_key: route_key,
      signature: signature,
      status: status,
      iur_hash: compile_result.iur_hash,
      previous_iur_hash: previous_hash,
      dsl_version: compile_result.dsl_version,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })
  end

  defp signature_payload(iur_document, dsl_version) do
    %{
      "dsl_version" => dsl_version,
      "root" => Map.get(iur_document, "root")
    }
  end

  defp complexity_class(iur_document) when is_map(iur_document) do
    node_count =
      iur_document
      |> Map.get("root")
      |> count_nodes()

    cond do
      node_count <= 0 -> "unknown"
      node_count <= 5 -> "small"
      node_count <= 25 -> "medium"
      true -> "large"
    end
  end

  defp complexity_class(_iur_document), do: "unknown"

  defp count_nodes(nil), do: 0

  defp count_nodes(node) when is_map(node) do
    children =
      case Map.get(node, "children") do
        list when is_list(list) -> list
        _ -> []
      end

    1 + Enum.reduce(children, 0, fn child, acc -> acc + count_nodes(child) end)
  end

  defp count_nodes(_node), do: 0

  defp preview_dsl_version(compile_request, continuity) do
    case extract_dsl_document(compile_request, continuity) do
      {:ok, dsl_document} ->
        normalize_string(get_value(dsl_document, :dsl_version)) || "unknown"

      _ ->
        "unknown"
    end
  end

  defp elapsed_ms(started_at_us) do
    duration_us = System.monotonic_time(:microsecond) - started_at_us
    max(duration_us / 1000.0, 0.0)
  end

  defp ensure_parity_table! do
    case :ets.whereis(@parity_table) do
      :undefined ->
        try do
          :ets.new(@parity_table, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])
        rescue
          ArgumentError -> @parity_table
        end

      _table ->
        @parity_table
    end
  end

  defp resolve_feature_flags(compile_request, opts) do
    request_flags =
      compile_request
      |> get_map(:policy_decision)
      |> get_map(:feature_flags)

    direct_flags = get_map(compile_request, :feature_flags)
    opts_flags = Keyword.get(opts, :feature_flags, %{})

    request_flags
    |> Map.merge(direct_flags)
    |> Map.merge(if(is_map(opts_flags), do: opts_flags, else: %{}))
  end

  defp resolve_policy_version(compile_request, opts) do
    normalize_string(Keyword.get(opts, :policy_version)) ||
      compile_request
      |> get_map(:policy_decision)
      |> get_value(:policy_version)
      |> normalize_string() ||
      "v1"
  end

  defp continuity_ids(compile_request, opts) do
    %{
      correlation_id:
        normalize_string(Keyword.get(opts, :correlation_id)) ||
          normalize_string(get_value(compile_request, :correlation_id)) ||
          default_id("cor"),
      request_id:
        normalize_string(Keyword.get(opts, :request_id)) ||
          normalize_string(get_value(compile_request, :request_id)) ||
          default_id("req")
    }
  end

  defp dsl_document_shape?(map) when is_map(map) do
    get_value(map, :dsl_version) != nil and get_value(map, :root) != nil
  end

  defp dsl_document_shape?(_map), do: false

  defp force_compile_failure?(compile_request) do
    get_value(compile_request, :force_error) == true or
      get_in(compile_request, [:command, :payload, :force_compile_error]) == true
  end

  defp validation_error(error_code, message, continuity, details) do
    compile_error(error_code, message, continuity,
      stage: @validation_stage,
      details: details
    )
  end

  defp compile_error(error_code, message, opts_or_continuity, extra_opts) do
    continuity = normalize_continuity(opts_or_continuity)

    TypedError.ingress(error_code, message,
      category: "compile",
      stage: Keyword.get(extra_opts, :stage, @compile_stage),
      details: Keyword.get(extra_opts, :details, %{}),
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    )
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

  defp normalize_continuity(_opts) do
    %{correlation_id: default_id("cor"), request_id: default_id("req")}
  end

  defp normalize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_value), do: nil

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []

  defp get_map(map, key) when is_map(map) do
    case get_value(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp get_map(_map, _key), do: %{}

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_value(_map, _key), do: nil

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
