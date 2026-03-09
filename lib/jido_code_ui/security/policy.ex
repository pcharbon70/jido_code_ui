defmodule JidoCodeUi.Security.Policy do
  @moduledoc """
  Runtime authorization and feature-flag governance service.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :security_policy
  @mutating_prefixes ["create_", "update_", "delete_", "save_", "apply_"]
  @mutation_roles MapSet.new(["admin", "editor"])

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec authorize(map(), map()) :: {:ok, map()} | {:error, TypedError.t()}
  def authorize(context, command) when is_map(context) and is_map(command) do
    request = build_request(context, command)

    cond do
      not request.actor.authenticated ->
        deny(request, "policy_auth_required", "Actor must be authenticated")

      request.command.mutating? and not actor_can_mutate?(request.actor) ->
        deny(
          request,
          "policy_mutation_denied",
          "Actor is not allowed to execute mutating commands"
        )

      request.command.custom_nodes != [] and not custom_nodes_enabled?(request) ->
        emit_custom_node_decision(request, :deny)

        deny(
          request,
          "policy_custom_node_denied",
          "Custom DSL node execution is disabled by feature flag"
        )

      true ->
        if request.command.custom_nodes != [] do
          emit_custom_node_decision(request, :allow)
        end

        {:ok,
         %{
           decision: :allow,
           policy_version: request.policy_version,
           request: request,
           feature_flags: request.feature_flags,
           metadata: %{
             mutating_command: request.command.mutating?,
             custom_nodes: request.command.custom_nodes
           }
         }}
    end
  end

  def authorize(_context, _command) do
    deny(
      %{
        policy_version: "v1",
        continuity: %{correlation_id: default_id("cor"), request_id: default_id("req")},
        actor: %{subject_id: "anonymous", actor_type: "unknown"},
        command: %{command_type: "unknown", custom_nodes: []},
        feature_flags: %{}
      },
      "policy_invalid_request",
      "Policy request must be maps"
    )
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp build_request(context, command) do
    policy_context = get_map(context, :policy_context)
    feature_flags = normalize_feature_flags(policy_context, context)
    actor = normalize_actor(context)
    continuity = normalize_continuity(context)
    command_metadata = normalize_command(command)

    %{
      actor: actor,
      command: command_metadata,
      continuity: continuity,
      feature_flags: feature_flags,
      policy_version: policy_version(policy_context),
      route_key: get_value(context, :route_key) || "route-unset"
    }
  end

  defp normalize_actor(context) do
    actor_source =
      case get_map(context, :actor) do
        map when map != %{} -> map
        _ -> get_map(context, :auth_context)
      end

    subject_id =
      get_value(actor_source, :subject_id) || get_value(actor_source, :actor_id) || "anonymous"

    actor_type = get_value(actor_source, :actor_type) || "user"
    roles = normalize_string_list(get_value(actor_source, :roles))
    authenticated = normalize_authenticated(actor_source, subject_id)

    %{
      subject_id: to_string(subject_id),
      actor_type: to_string(actor_type),
      roles: roles,
      authenticated: authenticated
    }
  end

  defp normalize_command(command) do
    command_type = get_value(command, :command_type) || "unknown_command"
    payload = get_map(command, :payload)
    custom_nodes = extract_custom_nodes(payload)

    %{
      command_type: to_string(command_type),
      mutating?: mutating_command?(command_type, payload),
      custom_nodes: custom_nodes
    }
  end

  defp normalize_continuity(context) do
    %{
      correlation_id: to_string(get_value(context, :correlation_id) || default_id("cor")),
      request_id: to_string(get_value(context, :request_id) || default_id("req"))
    }
  end

  defp normalize_feature_flags(policy_context, context) do
    policy_feature_flags =
      case policy_context do
        map when is_map(map) -> get_map(map, :feature_flags)
        _ -> %{}
      end

    context_feature_flags = get_map(context, :feature_flags)

    Map.merge(policy_feature_flags, context_feature_flags)
  end

  defp policy_version(policy_context) do
    case get_value(policy_context, :policy_version) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if byte_size(trimmed) > 0 do
          trimmed
        else
          "v1"
        end

      _ ->
        "v1"
    end
  end

  defp actor_can_mutate?(actor) do
    has_mutation_role? =
      actor.roles
      |> Enum.map(&String.downcase/1)
      |> Enum.any?(&MapSet.member?(@mutation_roles, &1))

    has_mutation_role? or actor.actor_type == "service"
  end

  defp custom_nodes_enabled?(request) do
    custom_dsl_nodes_enabled =
      case get_value(request.feature_flags, :custom_dsl_nodes) do
        true -> true
        "true" -> true
        1 -> true
        _ -> false
      end

    allowlist =
      request.feature_flags
      |> get_value(:custom_node_allowlist)
      |> normalize_string_list()
      |> MapSet.new()

    allowlist_ok? =
      MapSet.size(allowlist) == 0 or
        Enum.all?(request.command.custom_nodes, &MapSet.member?(allowlist, &1))

    custom_dsl_nodes_enabled and allowlist_ok?
  end

  defp mutating_command?(command_type, payload) do
    command_name = command_type |> to_string() |> String.downcase()
    payload_mutation_flag = get_value(payload, :mutates_session) == true

    payload_mutation_flag or Enum.any?(@mutating_prefixes, &String.starts_with?(command_name, &1))
  end

  defp extract_custom_nodes(payload) when is_map(payload) do
    custom_nodes =
      case get_value(payload, :custom_nodes) do
        nodes when is_list(nodes) -> nodes
        _ -> []
      end

    explicit_node =
      case get_value(payload, :custom_node_type) do
        node when is_binary(node) -> [node]
        _ -> []
      end

    (custom_nodes ++ explicit_node)
    |> normalize_string_list()
    |> Enum.uniq()
  end

  defp extract_custom_nodes(_payload), do: []

  defp deny(request, error_code, message) do
    typed_error =
      TypedError.ingress(error_code, message,
        category: "policy",
        stage: "policy_authorization",
        details: %{
          policy_version: request.policy_version,
          route_key: request.route_key,
          actor: %{
            subject_id: request.actor.subject_id,
            actor_type: request.actor.actor_type
          },
          command: %{
            command_type: request.command.command_type,
            custom_nodes: request.command.custom_nodes
          }
        },
        correlation_id: request.continuity.correlation_id,
        request_id: request.continuity.request_id
      )

    {:error, typed_error}
  end

  defp emit_custom_node_decision(request, :allow) do
    Telemetry.emit("ui.policy.custom_node.allow.v1", %{
      policy_version: request.policy_version,
      custom_nodes: request.command.custom_nodes,
      actor: request.actor.subject_id,
      correlation_id: request.continuity.correlation_id,
      request_id: request.continuity.request_id
    })
  end

  defp emit_custom_node_decision(request, :deny) do
    Telemetry.emit("ui.policy.custom_node.deny.v1", %{
      policy_version: request.policy_version,
      custom_nodes: request.command.custom_nodes,
      actor: request.actor.subject_id,
      correlation_id: request.continuity.correlation_id,
      request_id: request.continuity.request_id
    })
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) -> [String.trim(value)]
      value when is_atom(value) -> [value |> Atom.to_string() |> String.trim()]
      _ -> []
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_values), do: []

  defp normalize_authenticated(nil, _subject_id), do: false

  defp normalize_authenticated(actor_source, subject_id) do
    case get_value(actor_source, :authenticated) do
      value when is_boolean(value) -> value
      _ -> subject_id != "anonymous"
    end
  end

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
