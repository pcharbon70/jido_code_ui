defmodule JidoCodeUi.Conformance.ScenarioCatalogConformanceTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.ControlPlaneBoundary
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Security.Policy
  alias JidoCodeUi.Services.DslCompiler
  alias JidoCodeUi.Services.IurRenderer
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.Session.RuntimeAgent
  alias JidoCodeUi.TypedError

  @moduletag :conformance

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

  test "SCN-001 control-plane ownership consistency remains canonical" do
    runtime_modules = JidoCodeUi.Application.runtime_child_order()
    ownership = ControlPlaneBoundary.default_ownership()

    assert :ok = JidoCodeUi.Application.validate_runtime_wiring(runtime_modules, ownership)
    assert :ok = ControlPlaneBoundary.authorize_session_mutation(RuntimeAgent)

    assert {:error, %TypedError{error_code: "session_authority_violation", category: "boundary"}} =
             ControlPlaneBoundary.authorize_session_mutation(UiOrchestrator)
  end

  test "SCN-002 ingress validation behavior fails malformed envelopes closed" do
    assert {:error,
            %TypedError{
              error_code: "ingress_schema_invalid",
              category: "ingress",
              stage: "ingress_validation",
              correlation_id: "cor-scn-002"
            }} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-002",
               correlation_id: "cor-scn-002",
               request_id: "req-scn-002",
               payload: [:invalid],
               auth_context: editor_auth("v1")
             })

    refute Enum.any?(Telemetry.recent_events(300), fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-scn-002"
           end)
  end

  test "SCN-003 correlation continuity persists across compile, session, and render" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-003",
               correlation_id: "cor-scn-003",
               request_id: "req-scn-003",
               payload: %{path: "lib/scn003.ex", contents: "baseline"},
               auth_context: editor_auth("v2")
             })

    assert {:ok, result} = UiOrchestrator.execute(admitted, %{})

    assert result.continuity.correlation_id == "cor-scn-003"
    assert result.continuity.request_id == "req-scn-003"
    assert result.compile.compile_authority == "server"
    assert result.session.continuity.correlation_id == "cor-scn-003"
    assert result.session.continuity.request_id == "req-scn-003"
    assert result.render.continuity.correlation_id == "cor-scn-003"
    assert result.render.continuity.request_id == "req-scn-003"

    events = Telemetry.recent_events(500)

    assert_event_with_ids(events, "ui.dsl.compile.started.v1", "cor-scn-003", "req-scn-003")
    assert_event_with_ids(events, "ui.dsl.compile.completed.v1", "cor-scn-003", "req-scn-003")
    assert_event_with_ids(events, "ui.iur.render.started.v1", "cor-scn-003", "req-scn-003")
    assert_event_with_ids(events, "ui.iur.render.completed.v1", "cor-scn-003", "req-scn-003")
  end

  test "SCN-004 typed error normalization returns canonical categories and stages" do
    assert {:ok, admitted_compile_failure} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-004",
               correlation_id: "cor-scn-004-compile",
               request_id: "req-scn-004-compile",
               payload: %{path: "lib/scn004.ex", contents: "break", force_compile_error: true},
               auth_context: editor_auth("v1")
             })

    assert {:error,
            %TypedError{
              error_code: "orchestrator_compile_failed",
              category: "orchestration",
              stage: "orchestrator_compile"
            } = compile_error} = UiOrchestrator.execute(admitted_compile_failure, %{})

    assert TypedError.conformance(compile_error).status == :pass

    assert {:ok, admitted_render_failure} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-004",
               correlation_id: "cor-scn-004-render",
               request_id: "req-scn-004-render",
               payload: %{path: "lib/scn004.ex", contents: "break", force_render_error: true},
               auth_context: editor_auth("v1")
             })

    assert {:error,
            %TypedError{
              error_code: "orchestrator_render_failed",
              category: "orchestration",
              stage: "orchestrator_render"
            } = render_error} = UiOrchestrator.execute(admitted_render_failure, %{})

    assert TypedError.conformance(render_error).status == :pass
  end

  test "SCN-005 observability minimum baseline emits required compile/render telemetry families" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-005",
               correlation_id: "cor-scn-005",
               request_id: "req-scn-005",
               payload: %{path: "lib/scn005.ex", contents: "ok"},
               auth_context: editor_auth("v3")
             })

    assert {:ok, _result} = UiOrchestrator.execute(admitted, %{})

    events = Telemetry.recent_events(800)

    required_events = [
      "ui.command.received.v1",
      "ui.dsl.compile.started.v1",
      "ui.dsl.compile.completed.v1",
      "ui.dsl.compile.metric.v1",
      "ui.iur.render.started.v1",
      "ui.iur.render.completed.v1",
      "ui.iur.render.metric.v1",
      "ui.orchestrator.outcome.metric.v1"
    ]

    Enum.each(required_events, fn event_name ->
      assert Enum.any?(events, fn event ->
               event.event_name == event_name and
                 event.correlation_id == "cor-scn-005" and
                 event.request_id == "req-scn-005"
             end)
    end)
  end

  test "SCN-006 authorization enforcement denies unauthorized mutating commands" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-006",
               correlation_id: "cor-scn-006",
               request_id: "req-scn-006",
               payload: %{path: "lib/scn006.ex", contents: "blocked"},
               auth_context: viewer_auth("v6")
             })

    assert {:error,
            %TypedError{
              error_code: "policy_mutation_denied",
              category: "policy",
              stage: "policy_authorization"
            }} = UiOrchestrator.execute(admitted, %{})

    events = Telemetry.recent_events(500)

    assert_event_with_ids(events, "ui.policy.denied.v1", "cor-scn-006", "req-scn-006")

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.orchestrator.outcome.metric.v1" and
               event.outcome == "deny" and
               event.correlation_id == "cor-scn-006" and
               event.request_id == "req-scn-006"
           end)
  end

  test "SCN-007 sensitive data redaction removes secrets from deny-path telemetry" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-scn-007",
               correlation_id: "cor-scn-007",
               request_id: "req-scn-007",
               payload: %{
                 path: "lib/scn007.ex",
                 prompt: "secret prompt",
                 code: "token=abc123",
                 token: "tok-super-secret"
               },
               auth_context: viewer_auth("v7")
             })

    assert {:error,
            %TypedError{
              error_code: "policy_mutation_denied",
              category: "policy",
              stage: "policy_authorization"
            }} = UiOrchestrator.execute(admitted, %{})

    events = Telemetry.recent_events(800)

    denied_event =
      Enum.find(events, fn event ->
        event.event_name == "ui.policy.denied.v1" and
          event.correlation_id == "cor-scn-007" and
          event.request_id == "req-scn-007"
      end)

    assert denied_event != nil
    assert denied_event.redaction_applied == true
    assert get_in(denied_event, [:redacted_command, :payload, :prompt]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :code]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :token]) == "[REDACTED]"

    denied_inspect = inspect(denied_event)
    refute String.contains?(denied_inspect, "secret prompt")
    refute String.contains?(denied_inspect, "tok-super-secret")

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.redaction.applied.v1" and
               event.source_event == "ui.policy.denied.v1" and
               event.correlation_id == "cor-scn-007"
           end)
  end

  test "SCN-008 DSL/IUR schema compatibility enforces versions and custom-node policy" do
    unsupported_dsl = %{
      dsl_version: "v99",
      root: %{type: "layout.stack", children: [%{type: "widget.editor"}]}
    }

    assert {:error, %TypedError{error_code: "dsl_schema_incompatible", stage: "dsl_validation"}} =
             DslCompiler.compile(
               %{dsl_document: unsupported_dsl},
               correlation_id: "cor-scn-008-version",
               request_id: "req-scn-008-version"
             )

    custom_node_document = %{
      dsl_version: "v1",
      root: %{type: "layout.stack", children: [%{type: "custom.markdown.preview"}]}
    }

    assert {:error, %TypedError{error_code: "policy_custom_node_denied"}} =
             Policy.authorize(
               %{
                 correlation_id: "cor-scn-008-policy-deny",
                 request_id: "req-scn-008-policy-deny",
                 actor: %{subject_id: "usr-scn-008", roles: ["editor"], authenticated: true},
                 policy_context: %{
                   policy_version: "v8",
                   feature_flags: %{custom_dsl_nodes: false}
                 }
               },
               %{command_type: "save_file", payload: %{custom_nodes: ["markdown.preview"]}}
             )

    assert {:ok, _allow_policy} =
             Policy.authorize(
               %{
                 correlation_id: "cor-scn-008-policy-allow",
                 request_id: "req-scn-008-policy-allow",
                 actor: %{subject_id: "usr-scn-008", roles: ["editor"], authenticated: true},
                 policy_context: %{
                   policy_version: "v8",
                   feature_flags: %{
                     custom_dsl_nodes: true,
                     custom_node_allowlist: ["markdown.preview"]
                   }
                 }
               },
               %{command_type: "save_file", payload: %{custom_nodes: ["markdown.preview"]}}
             )

    assert {:error, %TypedError{error_code: "dsl_custom_node_disallowed"}} =
             DslCompiler.compile(
               %{dsl_document: custom_node_document},
               correlation_id: "cor-scn-008-custom-deny",
               request_id: "req-scn-008-custom-deny"
             )

    assert {:ok, compile_result} =
             DslCompiler.compile(
               %{dsl_document: custom_node_document},
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["markdown.preview"]
               },
               correlation_id: "cor-scn-008-custom-allow",
               request_id: "req-scn-008-custom-allow"
             )

    assert compile_result.compile_authority == "server"
    assert compile_result.iur_version == "v1"

    assert {:error,
            %TypedError{error_code: "iur_invalid_document", stage: "iur_render_validation"}} =
             IurRenderer.render(
               %{
                 route_key: "route-scn-008",
                 compile_result: %{
                   iur_document: compile_result.iur_document,
                   iur_hash: compile_result.iur_hash,
                   iur_version: "v99"
                 }
               },
               correlation_id: "cor-scn-008-iur-version",
               request_id: "req-scn-008-iur-version"
             )
  end

  defp assert_event_with_ids(events, event_name, correlation_id, request_id) do
    assert Enum.any?(events, fn event ->
             event.event_name == event_name and
               event.correlation_id == correlation_id and
               event.request_id == request_id
           end)
  end

  defp editor_auth(policy_version) do
    %{
      subject_id: "usr-conformance-editor",
      roles: ["editor"],
      authenticated: true,
      policy_context: %{policy_version: policy_version}
    }
  end

  defp viewer_auth(policy_version) do
    %{
      subject_id: "usr-conformance-viewer",
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
