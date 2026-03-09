defmodule JidoCodeUi.UiOrchestratorRoutingTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.TypedError

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

  test "execute routes deterministically with canonical pipeline ordering" do
    admitted =
      admit_command(%{
        correlation_id: "cor-route-001",
        request_id: "req-route-001",
        auth_context: %{
          subject_id: "usr-editor",
          roles: ["editor"],
          authenticated: true,
          policy_context: %{policy_version: "v2"}
        }
      })

    assert {:ok, first} = UiOrchestrator.execute(admitted, %{})
    assert {:ok, second} = UiOrchestrator.execute(admitted, %{})

    assert first.route_key == second.route_key
    assert first.stage_trace == [:validate, :policy, :compile, :session, :render]
    assert first.policy.policy_version == "v2"
    assert first.compile.compile_authority == "server"
  end

  test "execute fails closed on policy deny before compile and session stages" do
    admitted =
      admit_command(%{
        correlation_id: "cor-route-deny",
        request_id: "req-route-deny",
        auth_context: %{
          subject_id: "usr-viewer",
          roles: ["viewer"],
          authenticated: true,
          policy_context: %{policy_version: "v1"}
        }
      })

    assert {:error,
            %TypedError{
              category: "policy",
              stage: "policy_authorization",
              error_code: "policy_mutation_denied"
            }} = UiOrchestrator.execute(admitted, %{})

    events = Telemetry.recent_events(50)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.policy.denied.v1" and
               event.correlation_id == "cor-route-deny" and
               event.request_id == "req-route-deny"
           end)

    refute Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-route-deny"
           end)
  end

  test "execute emits redacted denied telemetry for sensitive command fields" do
    admitted =
      admit_command(%{
        correlation_id: "cor-route-redact",
        request_id: "req-route-redact",
        auth_context: %{
          subject_id: "usr-viewer",
          roles: ["viewer"],
          authenticated: true
        },
        payload: %{
          path: "lib/secret.ex",
          prompt: "very sensitive prompt",
          code: "secret code",
          contents: "full file contents"
        }
      })

    assert {:error, %TypedError{error_code: "policy_mutation_denied"}} =
             UiOrchestrator.execute(admitted, %{})

    denied_event =
      Telemetry.recent_events(100)
      |> Enum.find(fn event ->
        event.event_name == "ui.policy.denied.v1" and event.correlation_id == "cor-route-redact"
      end)

    assert denied_event != nil
    assert get_in(denied_event, [:redacted_command, :payload, :prompt]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :code]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :contents]) == "[REDACTED]"
  end

  test "execute returns typed validation errors for unsupported command shapes" do
    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_validate",
              error_code: "orchestrator_invalid_input"
            }} = UiOrchestrator.execute(%{foo: "bar"}, %{})
  end

  defp admit_command(overrides) do
    envelope =
      %{
        command_type: "save_file",
        session_id: "sess-route",
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
