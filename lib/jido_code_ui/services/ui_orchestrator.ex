defmodule JidoCodeUi.Services.UiOrchestrator do
  @moduledoc """
  Deterministic runtime orchestrator with explicit policy governance and
  stage-ordered execution.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Security.Policy
  alias JidoCodeUi.Services.DslCompiler
  alias JidoCodeUi.Services.IurRenderer
  alias JidoCodeUi.Session.RuntimeAgent
  alias JidoCodeUi.TypedError

  @ready_child_id :ui_orchestrator
  @pipeline_order [:validate, :policy, :compile, :session, :render]
  @sensitive_keys MapSet.new(["prompt", "code", "contents", "token", "secret", "api_key"])

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec execute(map(), map()) :: {:ok, map()} | {:error, TypedError.t()}
  def execute(command, context \\ %{}) when is_map(context) do
    with :ok <- StartupGuard.ensure_ready("orchestrator_execute", %{operation: "execute"}),
         {:ok, state} <- init_state(command, context),
         {:ok, state} <- stage_validate(state),
         {:ok, state} <- stage_policy(state),
         {:ok, state} <- stage_compile(state),
         {:ok, state} <- stage_session(state),
         {:ok, state} <- stage_render(state) do
      emit_outcome_metric("success", state)
      {:ok, success_output(state)}
    else
      {:error, %TypedError{} = typed_error} ->
        emit_outcome_metric(outcome_type(typed_error), typed_error)
        {:error, typed_error}
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp init_state(command, context) do
    {:ok,
     %{
       raw_command: command,
       raw_context: context,
       stage_index: -1,
       stage_trace: []
     }}
  end

  defp stage_validate(state) do
    with {:ok, state} <- advance_stage(state, :validate),
         {:ok, normalized_input} <- normalize_execute_input(state.raw_command, state.raw_context) do
      route_key = derive_route_key(normalized_input.envelope_kind, normalized_input.payload)

      command_received_payload = %{
        correlation_id: normalized_input.continuity.correlation_id,
        request_id: normalized_input.continuity.request_id,
        session_id: normalized_input.session_id,
        envelope_kind: to_string(normalized_input.envelope_kind),
        policy_version: normalized_input.policy_version
      }

      Telemetry.emit("ui.command.received.v1", command_received_payload)

      {:ok,
       state
       |> Map.put(:normalized_input, normalized_input)
       |> Map.put(:route_key, route_key)}
    end
  end

  defp stage_policy(state) do
    with {:ok, state} <- advance_stage(state, :policy),
         {:ok, decision} <- authorize(state) do
      {:ok, Map.put(state, :policy_decision, decision)}
    else
      {:error, %TypedError{} = typed_error} ->
        emit_policy_denied(state, typed_error)
        {:error, typed_error}
    end
  end

  defp stage_compile(state) do
    with {:ok, state} <- advance_stage(state, :compile) do
      input = state.normalized_input
      policy_version = state.policy_decision.policy_version
      compile_command = compile_command(input)

      Telemetry.emit("ui.dsl.compile.started.v1", %{
        route_key: state.route_key,
        policy_version: policy_version,
        correlation_id: input.continuity.correlation_id,
        request_id: input.continuity.request_id
      })

      case DslCompiler.compile(
             %{
               command: compile_command,
               envelope_kind: input.envelope_kind,
               route_key: state.route_key,
               policy_decision: state.policy_decision
             },
             policy_version: policy_version,
             feature_flags: state.policy_decision.feature_flags,
             correlation_id: input.continuity.correlation_id,
             request_id: input.continuity.request_id
           ) do
        {:ok, compile_result} ->
          Telemetry.emit("ui.dsl.compile.completed.v1", %{
            route_key: state.route_key,
            policy_version: policy_version,
            correlation_id: input.continuity.correlation_id,
            request_id: input.continuity.request_id
          })

          {:ok, Map.put(state, :compile_result, compile_result)}

        {:error, %TypedError{} = typed_error} ->
          retention_outcome = retain_last_known_good(state, "compile", typed_error)

          Telemetry.emit("ui.dsl.compile.failed.v1", %{
            route_key: state.route_key,
            policy_version: policy_version,
            error_code: typed_error.error_code,
            error_category: typed_error.category,
            error_stage: typed_error.stage,
            correlation_id: input.continuity.correlation_id,
            request_id: input.continuity.request_id
          })

          {:error,
           orchestration_error(
             state,
             "orchestrator_compile_failed",
             "Compile stage failed",
             "orchestrator_compile",
             Map.merge(
               %{cause: typed_error.error_code},
               retention_details(retention_outcome)
             )
           )}
      end
    end
  end

  defp stage_session(state) do
    with {:ok, state} <- advance_stage(state, :session) do
      input = state.normalized_input
      session_id = input.session_id || default_session_id(state.route_key)

      Telemetry.emit("ui.orchestrator.stage.session.v1", %{
        route_key: state.route_key,
        transition: "started",
        correlation_id: input.continuity.correlation_id,
        request_id: input.continuity.request_id
      })

      case RuntimeAgent.create_session(%{
             session_id: session_id,
             route_key: state.route_key,
             compile_result: state.compile_result,
             policy_version: state.policy_decision.policy_version,
             correlation_id: input.continuity.correlation_id,
             request_id: input.continuity.request_id
           }) do
        {:ok, snapshot} ->
          Telemetry.emit("ui.orchestrator.stage.session.v1", %{
            route_key: state.route_key,
            transition: "completed",
            correlation_id: input.continuity.correlation_id,
            request_id: input.continuity.request_id
          })

          {:ok, Map.put(state, :session_snapshot, snapshot)}

        {:error, %TypedError{} = typed_error} ->
          {:error,
           orchestration_error(
             state,
             "orchestrator_session_failed",
             "Session stage failed",
             "orchestrator_session",
             %{cause: typed_error.error_code}
           )}
      end
    end
  end

  defp stage_render(state) do
    with {:ok, state} <- advance_stage(state, :render) do
      input = state.normalized_input
      policy_version = state.policy_decision.policy_version

      Telemetry.emit("ui.iur.render.started.v1", %{
        route_key: state.route_key,
        policy_version: policy_version,
        correlation_id: input.continuity.correlation_id,
        request_id: input.continuity.request_id
      })

      case IurRenderer.render(
             %{
               compile_result: state.compile_result,
               session_snapshot: state.session_snapshot,
               route_key: state.route_key
             },
             policy_version: policy_version,
             correlation_id: input.continuity.correlation_id,
             request_id: input.continuity.request_id
           ) do
        {:ok, render_result} ->
          case RuntimeAgent.update_session(state.session_snapshot.session_id, %{
                 expected_revision: state.session_snapshot.revision,
                 route_key: state.route_key,
                 policy_version: policy_version,
                 compile_result: state.compile_result,
                 render_result: render_result,
                 correlation_id: input.continuity.correlation_id,
                 request_id: input.continuity.request_id
               }) do
            {:ok, updated_snapshot} ->
              Telemetry.emit("ui.iur.render.completed.v1", %{
                route_key: state.route_key,
                policy_version: policy_version,
                correlation_id: input.continuity.correlation_id,
                request_id: input.continuity.request_id
              })

              {:ok,
               state
               |> Map.put(:session_snapshot, updated_snapshot)
               |> Map.put(:render_result, render_result)}

            {:error, %TypedError{} = typed_error} ->
              {:error,
               orchestration_error(
                 state,
                 "orchestrator_session_failed",
                 "Session stage failed",
                 "orchestrator_session",
                 %{cause: typed_error.error_code}
               )}
          end

        {:error, %TypedError{} = typed_error} ->
          retention_outcome =
            retain_last_known_good(
              state,
              "render",
              typed_error,
              state.session_snapshot.revision
            )

          Telemetry.emit("ui.iur.render.failed.v1", %{
            route_key: state.route_key,
            policy_version: policy_version,
            error_code: typed_error.error_code,
            error_category: typed_error.category,
            error_stage: typed_error.stage,
            correlation_id: input.continuity.correlation_id,
            request_id: input.continuity.request_id
          })

          {:error,
           orchestration_error(
             state,
             "orchestrator_render_failed",
             "Render stage failed",
             "orchestrator_render",
             Map.merge(
               %{cause: typed_error.error_code},
               retention_details(retention_outcome)
             )
           )}
      end
    end
  end

  defp authorize(state) do
    input = state.normalized_input

    policy_context = %{
      correlation_id: input.continuity.correlation_id,
      request_id: input.continuity.request_id,
      auth_context: input.auth_context,
      actor: input.auth_context,
      policy_context: Map.merge(input.policy_context, %{policy_version: input.policy_version}),
      route_key: state.route_key
    }

    Policy.authorize(policy_context, input.payload)
  end

  defp normalize_execute_input(command, context) do
    with {:ok, envelope_kind, payload, envelope_context} <- extract_envelope(command),
         merged_context <- Map.merge(envelope_context, context),
         continuity <- continuity_ids(command, merged_context),
         auth_context <- select_auth_context(command, merged_context),
         policy_context <- select_policy_context(auth_context, merged_context) do
      {:ok,
       %{
         envelope_kind: envelope_kind,
         payload: payload,
         continuity: continuity,
         auth_context: auth_context,
         policy_context: policy_context,
         policy_version: policy_version(policy_context),
         session_id: session_id(payload, merged_context)
       }}
    else
      {:error, %TypedError{} = typed_error} -> {:error, typed_error}
    end
  end

  defp extract_envelope(command) do
    orchestrator_envelope = get_map(command, :orchestrator_envelope)

    cond do
      orchestrator_envelope != %{} and get_map(orchestrator_envelope, :payload) != %{} ->
        payload = get_map(orchestrator_envelope, :payload)
        context = get_map(orchestrator_envelope, :context)
        envelope_kind = get_value(context, :envelope_kind) || infer_envelope_kind(payload)

        if envelope_kind do
          {:ok, envelope_kind, payload, context}
        else
          {:error, invalid_execute_input("Unsupported orchestrator envelope payload")}
        end

      infer_envelope_kind(command) == :ui_command ->
        {:ok, :ui_command, command, %{}}

      infer_envelope_kind(command) == :widget_ui_event ->
        {:ok, :widget_ui_event, command, %{}}

      true ->
        {:error, invalid_execute_input("Unsupported orchestrator command payload")}
    end
  end

  defp infer_envelope_kind(payload) do
    cond do
      get_value(payload, :command_type) != nil ->
        :ui_command

      get_value(payload, :type) != nil and get_value(payload, :widget_id) != nil ->
        :widget_ui_event

      true ->
        nil
    end
  end

  defp continuity_ids(command, context) do
    correlation_id =
      get_value(context, :correlation_id) || get_value(command, :correlation_id) ||
        default_id("cor")

    request_id =
      get_value(context, :request_id) || get_value(command, :request_id) || default_id("req")

    %{correlation_id: to_string(correlation_id), request_id: to_string(request_id)}
  end

  defp select_auth_context(command, context) do
    auth_context =
      first_non_empty_map([
        get_map(context, :auth_context),
        get_map(command, :auth_context),
        get_map(context, :actor)
      ])

    if auth_context == %{} do
      %{
        subject_id: "anonymous",
        actor_type: "unknown",
        roles: [],
        authenticated: false
      }
    else
      auth_context
    end
  end

  defp select_policy_context(auth_context, context) do
    context_policy_context = get_map(context, :policy_context)
    auth_policy_context = get_map(auth_context, :policy_context)

    merged_feature_flags =
      Map.merge(
        get_map(auth_policy_context, :feature_flags),
        get_map(context_policy_context, :feature_flags)
      )

    auth_policy_context
    |> Map.merge(context_policy_context)
    |> put_feature_flags(merged_feature_flags)
  end

  defp session_id(payload, context) do
    get_value(payload, :session_id) || get_value(context, :session_id)
  end

  defp compile_command(%{envelope_kind: :widget_ui_event, payload: payload})
       when is_map(payload) do
    %{
      command_type: "widget_event",
      payload: payload
    }
  end

  defp compile_command(%{payload: payload}), do: payload

  defp derive_route_key(envelope_kind, payload) do
    digest = :erlang.phash2({envelope_kind, payload}, 1_000_000_000)
    "route-" <> Integer.to_string(digest)
  end

  defp advance_stage(state, stage) do
    expected_stage = Enum.at(@pipeline_order, state.stage_index + 1)

    if stage == expected_stage do
      {:ok,
       %{
         state
         | stage_index: state.stage_index + 1,
           stage_trace: state.stage_trace ++ [stage]
       }}
    else
      {:error,
       orchestration_error(
         state,
         "orchestrator_stage_order_violation",
         "Stage execution order was violated",
         "orchestrator_stage_order",
         %{
           expected_stage: expected_stage,
           attempted_stage: stage
         }
       )}
    end
  end

  defp orchestration_error(state, code, message, stage, details) do
    continuity = continuity_ids(state.raw_command || %{}, state.raw_context || %{})

    TypedError.ingress(code, message,
      category: "orchestration",
      stage: stage,
      details: Map.merge(details, %{route_key: Map.get(state, :route_key)}),
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    )
  end

  defp invalid_execute_input(message) do
    TypedError.ingress("orchestrator_invalid_input", message,
      category: "orchestration",
      stage: "orchestrator_validate"
    )
  end

  defp emit_policy_denied(state, typed_error) do
    input = Map.get(state, :normalized_input, %{})

    Telemetry.emit("ui.policy.denied.v1", %{
      route_key: Map.get(state, :route_key),
      policy_version:
        Map.get(typed_error.details || %{}, :policy_version) || input.policy_version,
      error_code: typed_error.error_code,
      error_category: typed_error.category,
      error_stage: typed_error.stage,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id,
      redacted_command: redact_sensitive(input.payload || %{})
    })
  end

  defp redact_sensitive(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      normalized_key = key |> to_string() |> String.downcase()

      if MapSet.member?(@sensitive_keys, normalized_key) do
        {key, "[REDACTED]"}
      else
        {key, redact_sensitive(nested_value)}
      end
    end)
    |> Map.new()
  end

  defp redact_sensitive(value) when is_list(value), do: Enum.map(value, &redact_sensitive/1)
  defp redact_sensitive(value), do: value

  defp success_output(state) do
    input = state.normalized_input

    continuity =
      input.continuity
      |> Map.put(:session_id, input.session_id)

    %{
      status: :ok,
      route_key: state.route_key,
      stage_trace: state.stage_trace,
      envelope_kind: input.envelope_kind,
      continuity: continuity,
      policy: %{
        decision: state.policy_decision.decision,
        policy_version: state.policy_decision.policy_version
      },
      compile: state.compile_result,
      session: state.session_snapshot,
      render: state.render_result
    }
  end

  defp emit_outcome_metric(outcome, state_or_error) do
    payload =
      case state_or_error do
        %TypedError{} = typed_error ->
          %{
            outcome: outcome,
            error_code: typed_error.error_code,
            error_category: typed_error.category,
            error_stage: typed_error.stage,
            correlation_id: typed_error.correlation_id,
            request_id: typed_error.request_id
          }

        state when is_map(state) ->
          input = state.normalized_input

          %{
            outcome: outcome,
            route_key: state.route_key,
            policy_version: state.policy_decision.policy_version,
            correlation_id: input.continuity.correlation_id,
            request_id: input.continuity.request_id
          }
      end

    Telemetry.emit("ui.orchestrator.outcome.metric.v1", payload)
  end

  defp retain_last_known_good(
         state,
         failed_stage,
         %TypedError{} = cause_error,
         expected_revision \\ nil
       ) do
    input = state.normalized_input
    session_id = input.session_id || default_session_id(state.route_key)

    retention_attrs =
      %{
        retention: %{
          failed_stage: failed_stage,
          error_code: cause_error.error_code,
          error_category: cause_error.category,
          error_stage: cause_error.stage,
          details: cause_error.details || %{}
        },
        correlation_id: input.continuity.correlation_id,
        request_id: input.continuity.request_id
      }
      |> maybe_put_expected_revision(expected_revision)

    case RuntimeAgent.update_session(session_id, retention_attrs) do
      {:ok, snapshot} ->
        %{
          status: rollback_status(snapshot),
          session_id: snapshot.session_id,
          error_code: nil
        }

      {:error, %TypedError{error_code: "session_not_found"}} ->
        %{
          status: "retention_not_applicable",
          session_id: session_id,
          error_code: "session_not_found"
        }

      {:error, %TypedError{} = typed_error} ->
        %{
          status: "retention_update_failed",
          session_id: session_id,
          error_code: typed_error.error_code
        }
    end
  end

  defp retention_details(retention_outcome) do
    %{
      retention_status: Map.get(retention_outcome, :status),
      retention_session_id: Map.get(retention_outcome, :session_id),
      retention_error_code: Map.get(retention_outcome, :error_code)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp rollback_status(snapshot) do
    case get_in(snapshot, [:rollback, :status]) do
      value when is_binary(value) and value != "" -> value
      _ -> "retention_applied"
    end
  end

  defp maybe_put_expected_revision(attrs, revision) when is_integer(revision) do
    Map.put(attrs, :expected_revision, revision)
  end

  defp maybe_put_expected_revision(attrs, _revision), do: attrs

  defp outcome_type(%TypedError{category: "policy"}), do: "deny"

  defp outcome_type(%TypedError{error_code: error_code}) when is_binary(error_code) do
    if String.starts_with?(error_code, "policy_"), do: "deny", else: "failure"
  end

  defp first_non_empty_map(maps) do
    Enum.find(maps, %{}, fn map -> is_map(map) and map != %{} end)
  end

  defp get_map(map, key) when is_map(map) do
    case get_value(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp get_map(_map, _key), do: %{}

  defp put_feature_flags(policy_context, feature_flags) do
    if feature_flags == %{} do
      policy_context
    else
      Map.put(policy_context, :feature_flags, feature_flags)
    end
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_value(_map, _key), do: nil

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

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp default_session_id(route_key) do
    "sess-orc-" <> Integer.to_string(:erlang.phash2(route_key, 1_000_000))
  end
end
