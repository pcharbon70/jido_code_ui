defmodule JidoCodeUi.RuntimeSubstrateIngressIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
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

  test "malformed payload and rejection scenarios fail closed before dispatch" do
    assert {:error,
            %TypedError{
              error_code: "ingress_schema_invalid",
              stage: "ingress_validation"
            }} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-bad-command",
               correlation_id: "cor-bad-command",
               request_id: "req-bad-command",
               payload: [:invalid],
               auth_context: valid_auth_context()
             })

    assert {:error,
            %TypedError{
              error_code: "ingress_schema_invalid",
              stage: "ingress_validation"
            }} =
             Substrate.admit(%{
               type: "unified.button.clicked",
               widget_id: "widget-bad-event",
               correlation_id: "cor-bad-event",
               request_id: "req-bad-event",
               data: "not-a-map",
               auth_context: valid_auth_context()
             })

    events = Telemetry.recent_events(100)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.ingress.denied.v1" and
               event.error_code == "ingress_schema_invalid"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.ingress.failure.metric.v1" and
               event.failure_class == "malformed"
           end)

    refute Enum.any?(events, fn event ->
             event.event_name == "ui.command.received.v1" and
               event.correlation_id in ["cor-bad-command", "cor-bad-event"]
           end)
  end

  test "continuity and auth propagation scenarios preserve admitted context" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-integration",
               correlation_id: "cor-integration",
               request_id: "req-integration",
               payload: %{path: "lib/app.ex", contents: "hello"},
               auth_context: %{
                 subject_id: "usr-integration",
                 roles: ["editor"],
                 scopes: ["files:write"],
                 policy_context: %{policy_version: "v3"}
               }
             })

    assert admitted.orchestrator_envelope.context.correlation_id == "cor-integration"
    assert admitted.orchestrator_envelope.context.request_id == "req-integration"
    assert admitted.orchestrator_envelope.context.auth_context.subject_id == "usr-integration"
    assert admitted.orchestrator_envelope.context.policy_context.policy_version == "v3"

    assert {:error,
            %TypedError{
              error_code: "ingress_auth_missing",
              stage: "ingress_auth",
              correlation_id: "cor-auth-missing",
              request_id: "req-auth-missing"
            }} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-auth-missing",
               correlation_id: "cor-auth-missing",
               request_id: "req-auth-missing",
               payload: %{path: "lib/app.ex"}
             })
  end

  defp valid_auth_context do
    %{
      subject_id: "usr-test",
      roles: ["editor"],
      scopes: ["files:read"],
      policy_version: "v1"
    }
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
