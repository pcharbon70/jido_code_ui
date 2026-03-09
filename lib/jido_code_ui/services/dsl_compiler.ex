defmodule JidoCodeUi.Services.DslCompiler do
  @moduledoc """
  Server-authoritative DSL compiler with schema validation and compatibility
  checks.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :dsl_compiler
  @supported_dsl_versions MapSet.new(["v1"])
  @validation_stage "dsl_validation"
  @compile_stage "dsl_compile"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec compile(map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def compile(compile_request, opts \\ [])

  def compile(compile_request, opts) when is_map(compile_request) and is_list(opts) do
    with :ok <- StartupGuard.ensure_ready("dsl_compile", %{operation: "compile"}) do
      if force_compile_failure?(compile_request) do
        {:error,
         compile_error("dsl_compile_failed", "DSL compile failed", opts,
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
          {:ok,
           %{
             compile_authority: "server",
             dsl_version: normalized.dsl_version,
             dsl_document: normalized.dsl_document,
             compile_opts: opts
           }}
        end
      end
    end
  end

  def compile(_compile_request, opts) when is_list(opts) do
    {:error,
     compile_error("dsl_compile_invalid_request", "Compile request must be a map", opts,
       stage: @validation_stage,
       details: %{schema_path: "$", expected: "map", received: "non-map"}
     )}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
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

    from_tree =
      dsl_document
      |> get_map(:root)
      |> collect_tree_custom_nodes()

    (from_document ++ from_tree)
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
