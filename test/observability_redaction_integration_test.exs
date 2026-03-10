defmodule JidoCodeUi.ObservabilityRedactionIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.TypedError

  @moduletag :integration

  setup do
    :ok = Telemetry.reset_events()

    defaults = JidoCodeUi.Application.runtime_ready_children()
    :ok = StartupLifecycle.set_expected_children(defaults)

    on_exit(fn ->
      :ok = StartupLifecycle.set_expected_children(defaults)
      :ok = Telemetry.reset_events()
    end)

    assert_eventually(fn -> StartupLifecycle.ready?() end)
    :ok
  end

  test "telemetry completeness integration covers lifecycle families, deny/reject paths, and join keys" do
    assert {:ok, admitted_success} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-obs-complete-success",
               correlation_id: "cor-obs-complete-success",
               request_id: "req-obs-complete-success",
               payload: %{path: "lib/obs_complete.ex", contents: "baseline"},
               auth_context: editor_auth("v2")
             })

    assert {:ok, _result} = UiOrchestrator.execute(admitted_success, %{})

    assert {:ok, admitted_deny} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-obs-complete-deny",
               correlation_id: "cor-obs-complete-deny",
               request_id: "req-obs-complete-deny",
               payload: %{path: "lib/obs_complete.ex", contents: "blocked"},
               auth_context: viewer_auth("v2")
             })

    assert {:error,
            %TypedError{
              category: "policy",
              stage: "policy_authorization",
              error_code: "policy_mutation_denied"
            }} = UiOrchestrator.execute(admitted_deny, %{})

    assert {:error,
            %TypedError{
              category: "ingress",
              stage: "ingress_validation",
              error_code: "ingress_schema_invalid"
            }} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-obs-complete-reject",
               correlation_id: "cor-obs-complete-reject",
               request_id: "req-obs-complete-reject",
               payload: [:invalid],
               auth_context: editor_auth("v2")
             })

    events = Telemetry.recent_events(800)

    assert_event_with_ids(events, "ui.dsl.compile.started.v1", "cor-obs-complete-success")
    assert_event_with_ids(events, "ui.dsl.compile.completed.v1", "cor-obs-complete-success")
    assert_event_with_ids(events, "ui.iur.render.started.v1", "cor-obs-complete-success")
    assert_event_with_ids(events, "ui.iur.render.completed.v1", "cor-obs-complete-success")

    assert_event_with_ids(events, "ui.policy.denied.v1", "cor-obs-complete-deny")
    assert_event_with_ids(events, "ui.ingress.denied.v1", "cor-obs-complete-reject")

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.ingress.failure.metric.v1" and
               event.correlation_id == "cor-obs-complete-reject" and
               event.failure_class == "malformed"
           end)

    required_join_key_events = [
      "ui.command.received.v1",
      "ui.dsl.compile.started.v1",
      "ui.dsl.compile.completed.v1",
      "ui.iur.render.started.v1",
      "ui.iur.render.completed.v1",
      "ui.policy.denied.v1",
      "ui.ingress.denied.v1"
    ]

    Enum.each(required_join_key_events, fn event_name ->
      assert Enum.any?(events, fn event ->
               event.event_name == event_name and
                 present?(event.correlation_id) and
                 present?(event.request_id)
             end)
    end)
  end

  test "redaction and typed error integration covers sensitive field redaction and diagnostics" do
    assert {:ok, admitted_redaction_deny} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-obs-redaction-deny",
               correlation_id: "cor-obs-redaction-deny",
               request_id: "req-obs-redaction-deny",
               payload: %{
                 path: "lib/private.ex",
                 prompt: "write secret payload",
                 code: "token=abc123",
                 token: "tok-secret-value",
                 note: "Bearer abcdefghijklmnop.qrstuvwx.yz012345"
               },
               auth_context: viewer_auth("v7")
             })

    assert {:error,
            %TypedError{
              category: "policy",
              stage: "policy_authorization",
              error_code: "policy_mutation_denied"
            }} = UiOrchestrator.execute(admitted_redaction_deny, %{})

    assert {:ok, admitted_compile_fail} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-obs-redaction-compile",
               correlation_id: "cor-obs-redaction-compile",
               request_id: "req-obs-redaction-compile",
               payload: %{
                 path: "lib/private.ex",
                 contents: "change",
                 force_compile_error: true
               },
               auth_context: editor_auth("v7")
             })

    assert {:error,
            %TypedError{
              category: "orchestration",
              stage: "orchestrator_compile",
              error_code: "orchestrator_compile_failed"
            }} = UiOrchestrator.execute(admitted_compile_fail, %{})

    assert {:ok, _admitted_widget} =
             Substrate.admit(%{
               type: "unified.button.clicked",
               widget_id: "widget-obs-redaction",
               correlation_id: "cor-obs-redaction-widget",
               request_id: "req-obs-redaction-widget",
               data: %{action: "run"},
               auth_context: editor_auth("v7")
             })

    events = Telemetry.recent_events(1200)

    denied_event =
      Enum.find(events, fn event ->
        event.event_name == "ui.policy.denied.v1" and
          event.correlation_id == "cor-obs-redaction-deny"
      end)

    assert denied_event != nil
    assert denied_event.redaction_applied == true
    assert denied_event.redaction_policy_version == "v1"
    assert get_in(denied_event, [:redacted_command, :payload, :prompt]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :code]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :token]) == "[REDACTED]"
    assert denied_event.error_category == "policy"
    assert denied_event.error_stage == "policy_authorization"

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.failed.v1" and
               event.correlation_id == "cor-obs-redaction-compile" and
               event.error_category == "compile" and
               event.error_stage == "dsl_compile"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.conformance.v1" and
               event.correlation_id == "cor-obs-redaction-compile" and
               event.error_code == "dsl_compile_failed" and
               event.status == "pass"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.redaction.applied.v1" and
               event.source_event == "ui.policy.denied.v1" and
               event.correlation_id == "cor-obs-redaction-deny"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.redaction.miss.v1" and
               event.source_event == "ui.policy.denied.v1" and
               event.correlation_id == "cor-obs-redaction-deny" and
               event.error_code == "redaction_policy_miss"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.telemetry.validation.failed.v1" and
               event.source_event == "ui.command.received.v1" and
               event.correlation_id == "cor-obs-redaction-widget" and
               "session_id" in event.missing_keys
           end)
  end

  defp assert_event_with_ids(events, event_name, correlation_id) do
    assert Enum.any?(events, fn event ->
             event.event_name == event_name and
               event.correlation_id == correlation_id and
               present?(event.request_id)
           end)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp editor_auth(policy_version) do
    %{
      subject_id: "usr-observability-editor",
      roles: ["editor"],
      authenticated: true,
      policy_context: %{policy_version: policy_version}
    }
  end

  defp viewer_auth(policy_version) do
    %{
      subject_id: "usr-observability-viewer",
      roles: ["viewer"],
      authenticated: true,
      policy_context: %{policy_version: policy_version}
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
