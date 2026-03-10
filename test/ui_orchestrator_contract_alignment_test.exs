defmodule JidoCodeUi.UiOrchestratorContractAlignmentTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Contracts.CompileResult
  alias JidoCodeUi.Contracts.OrchestratorResult
  alias JidoCodeUi.Contracts.RenderResult
  alias JidoCodeUi.Contracts.UiSessionSnapshot
  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.Session.RuntimeAgent
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

    assert %OrchestratorResult{} = result
    assert result.status == :ok
    assert is_binary(result.route_key)
    assert result.envelope_kind == :ui_command
    assert result.stage_trace == [:validate, :policy, :compile, :session, :render]
    assert result.policy.decision == :allow
    assert result.policy.policy_version == "v2"
    assert %CompileResult{} = result.compile
    assert result.compile.compile_authority == "server"
    assert %UiSessionSnapshot{} = result.session
    assert %RenderResult{} = result.render
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
               event.error_category == "policy" and
               event.error_stage == "policy_authorization" and
               event.correlation_id == "cor-contract-deny"
           end)

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "deny" and
               event.correlation_id == "cor-contract-deny"
           end)
  end

  test "widget event execution omits session join keys from command-received telemetry" do
    admitted =
      admit_widget_event(%{
        correlation_id: "cor-contract-widget",
        request_id: "req-contract-widget",
        auth_context: editor_auth("v4")
      })

    assert {:ok, result} = UiOrchestrator.execute(admitted, %{})
    assert result.envelope_kind == :widget_ui_event
    assert is_binary(result.session.session_id)
    assert result.session.session_id != "nil"
    assert String.starts_with?(result.session.session_id, "sess-")

    widget_command_events =
      Telemetry.recent_events(150)
      |> Enum.filter(fn event ->
        event.event_name == "ui.command.received.v1" and
          event.correlation_id == "cor-contract-widget"
      end)

    assert length(widget_command_events) >= 2

    assert Enum.all?(widget_command_events, fn event ->
             event.envelope_kind == "widget_ui_event" and not Map.has_key?(event, :session_id)
           end)

    session_transition_events =
      Telemetry.recent_events(150)
      |> Enum.filter(fn event ->
        event.event_name == "ui.session.transition.v1" and
          event.correlation_id == "cor-contract-widget"
      end)

    assert session_transition_events != []

    assert Enum.all?(session_transition_events, fn event ->
             is_binary(event.session_id) and event.session_id != "nil"
           end)

    refute Enum.any?(Telemetry.recent_events(150), fn event ->
             event.event_name == "ui.telemetry.validation.failed.v1" and
               event.source_event == "ui.command.received.v1" and
               event.correlation_id == "cor-contract-widget" and
               "session_id" in event.missing_keys
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
             event.event_name == "ui.dsl.compile.failed.v1" and
               event.policy_version == "v1" and
               event.error_category == "compile" and
               event.error_stage == "dsl_compile" and
               event.correlation_id == "cor-contract-compile-fail"
           end)

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

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.iur.render.failed.v1" and
               event.policy_version == "v1" and
               event.error_category == "render" and
               event.error_stage == "iur_render_adapter" and
               event.correlation_id == "cor-contract-render-fail"
           end)
  end

  test "compile failure paths retain last-known-good session projection metadata" do
    baseline =
      admit_command(%{
        session_id: "sess-contract-retain-compile",
        correlation_id: "cor-contract-retain-compile-baseline",
        request_id: "req-contract-retain-compile-baseline",
        auth_context: editor_auth("v3"),
        payload: %{path: "lib/retain_compile.ex", contents: "baseline"}
      })

    assert {:ok, _baseline_result} = UiOrchestrator.execute(baseline, %{})
    assert {:ok, before_failure} = RuntimeAgent.current_snapshot("sess-contract-retain-compile")
    assert before_failure.render.rendered == true

    failed_compile =
      admit_command(%{
        session_id: "sess-contract-retain-compile",
        correlation_id: "cor-contract-retain-compile-fail",
        request_id: "req-contract-retain-compile-fail",
        auth_context: editor_auth("v3"),
        payload: %{
          path: "lib/retain_compile.ex",
          contents: "break",
          force_compile_error: true
        }
      })

    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_compile",
              error_code: "orchestrator_compile_failed",
              details: details
            }} = UiOrchestrator.execute(failed_compile, %{})

    assert Map.get(details, :retention_status) == "retained_last_known_good"
    assert Map.get(details, :retention_session_id) == "sess-contract-retain-compile"
    assert Map.get(details, :retention_error_code) == nil

    assert {:ok, after_failure} = RuntimeAgent.current_snapshot("sess-contract-retain-compile")

    assert after_failure.active_iur_hash == before_failure.active_iur_hash
    assert after_failure.render == before_failure.render
    assert after_failure.rollback.status == "retained_last_known_good"
    assert after_failure.rollback.failed_stage == "compile"
    assert after_failure.rollback.failed_error_code == "dsl_compile_failed"
  end

  test "render failure paths retain last-known-good session projection metadata" do
    baseline =
      admit_command(%{
        session_id: "sess-contract-retain-render",
        correlation_id: "cor-contract-retain-render-baseline",
        request_id: "req-contract-retain-render-baseline",
        auth_context: editor_auth("v3"),
        payload: %{path: "lib/retain_render.ex", contents: "baseline"}
      })

    assert {:ok, _baseline_result} = UiOrchestrator.execute(baseline, %{})
    assert {:ok, before_failure} = RuntimeAgent.current_snapshot("sess-contract-retain-render")
    assert before_failure.render.rendered == true

    failed_render =
      admit_command(%{
        session_id: "sess-contract-retain-render",
        correlation_id: "cor-contract-retain-render-fail",
        request_id: "req-contract-retain-render-fail",
        auth_context: editor_auth("v3"),
        payload: %{
          path: "lib/retain_render.ex",
          contents: "changed",
          force_render_error: true
        }
      })

    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_render",
              error_code: "orchestrator_render_failed",
              details: details
            }} = UiOrchestrator.execute(failed_render, %{})

    assert Map.get(details, :retention_status) == "retained_last_known_good"
    assert Map.get(details, :retention_session_id) == "sess-contract-retain-render"
    assert Map.get(details, :retention_error_code) == nil

    assert {:ok, after_failure} = RuntimeAgent.current_snapshot("sess-contract-retain-render")

    assert after_failure.active_iur_hash == before_failure.active_iur_hash
    assert after_failure.render == before_failure.render
    assert after_failure.rollback.status == "retained_last_known_good"
    assert after_failure.rollback.failed_stage == "render"
    assert after_failure.rollback.failed_error_code == "iur_adapter_failed"
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

  defp admit_widget_event(overrides) do
    base = %{
      type: "unified.button.clicked",
      widget_id: "wid-contract-widget",
      correlation_id: "cor-widget-default",
      request_id: "req-widget-default",
      data: %{action: "run"},
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
