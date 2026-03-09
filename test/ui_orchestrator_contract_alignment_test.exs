defmodule JidoCodeUi.UiOrchestratorContractAlignmentTest do
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

  test "execute emits typed success output contract aligned to compile/session/render stages" do
    admitted =
      admit_command(%{
        correlation_id: "cor-contract-success",
        request_id: "req-contract-success",
        auth_context: editor_auth("v2")
      })

    assert {:ok, result} = UiOrchestrator.execute(admitted, %{})

    assert result.status == :ok
    assert is_binary(result.route_key)
    assert result.envelope_kind == :ui_command
    assert result.stage_trace == [:validate, :policy, :compile, :session, :render]
    assert result.policy.decision == :allow
    assert result.policy.policy_version == "v2"
    assert result.compile.compile_authority == "server"
    assert is_map(result.session)
    assert result.render.rendered == true
    assert result.continuity.correlation_id == "cor-contract-success"
    assert result.continuity.request_id == "req-contract-success"

    assert_event("ui.command.received.v1", "cor-contract-success")
    assert_event("ui.dsl.compile.started.v1", "cor-contract-success")
    assert_event("ui.dsl.compile.completed.v1", "cor-contract-success")
    assert_event("ui.iur.render.started.v1", "cor-contract-success")
    assert_event("ui.iur.render.completed.v1", "cor-contract-success")

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "success" and
               event.correlation_id == "cor-contract-success"
           end)
  end

  test "execute emits typed deny output contract and policy-denied telemetry" do
    admitted =
      admit_command(%{
        correlation_id: "cor-contract-deny",
        request_id: "req-contract-deny",
        auth_context: viewer_auth("v9")
      })

    assert {:error,
            %TypedError{
              category: "policy",
              stage: "policy_authorization",
              error_code: "policy_mutation_denied"
            }} = UiOrchestrator.execute(admitted, %{})

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.policy.denied.v1" and
               event.policy_version == "v9" and
               event.correlation_id == "cor-contract-deny"
           end)

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "deny" and
               event.correlation_id == "cor-contract-deny"
           end)
  end

  test "execute returns stage-specific typed failures for compile stage failures" do
    admitted =
      admit_command(%{
        correlation_id: "cor-contract-compile-fail",
        request_id: "req-contract-compile-fail",
        auth_context: editor_auth("v1"),
        payload: %{
          path: "lib/app.ex",
          contents: "hello",
          force_compile_error: true
        }
      })

    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_compile",
              error_code: "orchestrator_compile_failed"
            }} = UiOrchestrator.execute(admitted, %{})

    assert_event("ui.dsl.compile.failed.v1", "cor-contract-compile-fail")

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "failure" and
               event.correlation_id == "cor-contract-compile-fail"
           end)
  end

  test "execute returns stage-specific typed failures for render stage failures" do
    admitted =
      admit_command(%{
        correlation_id: "cor-contract-render-fail",
        request_id: "req-contract-render-fail",
        auth_context: editor_auth("v1"),
        payload: %{
          path: "lib/app.ex",
          contents: "hello",
          force_render_error: true
        }
      })

    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_render",
              error_code: "orchestrator_render_failed"
            }} = UiOrchestrator.execute(admitted, %{})

    assert_event("ui.iur.render.failed.v1", "cor-contract-render-fail")
  end

  defp admit_command(overrides) do
    base = %{
      command_type: "save_file",
      session_id: "sess-contract",
      correlation_id: "cor-default",
      request_id: "req-default",
      payload: %{path: "lib/app.ex", contents: "hello"},
      auth_context: editor_auth("v1")
    }

    {:ok, admitted} = Substrate.admit(Map.merge(base, overrides))
    admitted
  end

  defp editor_auth(policy_version) do
    %{
      subject_id: "usr-editor",
      roles: ["editor"],
      authenticated: true,
      policy_context: %{policy_version: policy_version}
    }
  end

  defp viewer_auth(policy_version) do
    %{
      subject_id: "usr-viewer",
      roles: ["viewer"],
      authenticated: true,
      policy_context: %{policy_version: policy_version}
    }
  end

  defp assert_event(event_name, correlation_id) do
    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == event_name and event.correlation_id == correlation_id
           end)
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
