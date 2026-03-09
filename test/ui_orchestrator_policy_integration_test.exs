defmodule JidoCodeUi.UiOrchestratorPolicyIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.TypedError

  @moduletag :integration

  setup do
    Telemetry.reset_events()

    defaults = JidoCodeUi.Application.runtime_ready_children()
    :ok = StartupLifecycle.set_expected_children(defaults)

    on_exit(fn ->
      :ok = StartupLifecycle.set_expected_children(defaults)
      :ok = Telemetry.reset_events()
    end)

    assert_eventually(fn -> StartupLifecycle.ready?() end)
    :ok
  end

  test "policy allow/deny scenarios gate compile deterministically and enforce custom-node flags" do
    allowed =
      admit(%{
        correlation_id: "cor-int-allow",
        request_id: "req-int-allow",
        auth_context: %{
          subject_id: "usr-editor",
          roles: ["editor"],
          authenticated: true,
          policy_context: %{
            policy_version: "v3",
            feature_flags: %{
              custom_dsl_nodes: true,
              custom_node_allowlist: ["markdown.preview"]
            }
          }
        },
        payload: %{path: "lib/app.ex", custom_nodes: ["markdown.preview"]}
      })

    assert {:ok, allow_result} = UiOrchestrator.execute(allowed, %{})
    assert allow_result.policy.policy_version == "v3"
    assert allow_result.compile.compile_authority == "server"

    unauthorized =
      admit(%{
        correlation_id: "cor-int-deny-auth",
        request_id: "req-int-deny-auth",
        auth_context: %{
          subject_id: "usr-viewer",
          roles: ["viewer"],
          authenticated: true,
          policy_context: %{policy_version: "v3"}
        }
      })

    assert {:error, %TypedError{error_code: "policy_mutation_denied"}} =
             UiOrchestrator.execute(unauthorized, %{})

    custom_node_disabled =
      admit(%{
        correlation_id: "cor-int-deny-node",
        request_id: "req-int-deny-node",
        auth_context: %{
          subject_id: "usr-editor",
          roles: ["editor"],
          authenticated: true,
          policy_context: %{
            policy_version: "v3",
            feature_flags: %{custom_dsl_nodes: false}
          }
        },
        payload: %{path: "lib/app.ex", custom_nodes: ["markdown.preview"]}
      })

    assert {:error, %TypedError{error_code: "policy_custom_node_denied"}} =
             UiOrchestrator.execute(custom_node_disabled, %{})

    events = Telemetry.recent_events(200)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-int-allow"
           end)

    refute Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id in ["cor-int-deny-auth", "cor-int-deny-node"]
           end)
  end

  test "orchestrator routing and denied-path scenarios are deterministic and redaction-safe" do
    base_envelope = %{
      correlation_id: "cor-int-route",
      request_id: "req-int-route",
      auth_context: %{
        subject_id: "usr-editor",
        roles: ["editor"],
        authenticated: true,
        policy_context: %{policy_version: "v1"}
      },
      payload: %{path: "lib/app.ex", contents: "hello"}
    }

    first = admit(base_envelope)

    second =
      admit(
        Map.merge(base_envelope, %{"payload" => %{"contents" => "hello", "path" => "lib/app.ex"}})
      )

    assert {:ok, first_result} = UiOrchestrator.execute(first, %{})
    assert {:ok, second_result} = UiOrchestrator.execute(second, %{})

    assert first_result.route_key == second_result.route_key
    assert first_result.stage_trace == second_result.stage_trace

    denied =
      admit(%{
        correlation_id: "cor-int-redact",
        request_id: "req-int-redact",
        auth_context: %{
          subject_id: "usr-viewer",
          roles: ["viewer"],
          authenticated: true,
          policy_context: %{policy_version: "v5"}
        },
        payload: %{
          path: "lib/secret.ex",
          prompt: "private prompt",
          code: "secret code",
          contents: "private file"
        }
      })

    assert {:error,
            %TypedError{
              error_code: "policy_mutation_denied",
              category: "policy",
              stage: "policy_authorization",
              correlation_id: "cor-int-redact",
              request_id: "req-int-redact"
            }} = UiOrchestrator.execute(denied, %{})

    denied_event =
      Telemetry.recent_events(200)
      |> Enum.find(fn event ->
        event.event_name == "ui.policy.denied.v1" and event.correlation_id == "cor-int-redact"
      end)

    assert denied_event != nil
    assert get_in(denied_event, [:redacted_command, :payload, :prompt]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :code]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :contents]) == "[REDACTED]"

    assert Enum.any?(Telemetry.recent_events(200), fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "deny" and
               event.correlation_id == "cor-int-redact"
           end)
  end

  defp admit(overrides) do
    envelope =
      %{
        command_type: "save_file",
        session_id: "sess-integration",
        correlation_id: "cor-default",
        request_id: "req-default",
        payload: %{path: "lib/app.ex", contents: "hello"},
        auth_context: %{
          subject_id: "usr-editor",
          roles: ["editor"],
          authenticated: true,
          policy_context: %{policy_version: "v1"}
        }
      }
      |> Map.merge(overrides)

    {:ok, admitted} = Substrate.admit(envelope)
    admitted
  end

  defp assert_eventually(fun, attempts \\ 30)

  defp assert_eventually(fun, 0) do
    assert fun.()
  end

  defp assert_eventually(fun, attempts) do
    if fun.() do
      assert true
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end
end
