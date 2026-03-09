defmodule JidoCodeUi.RuntimeSubstrateSchemaNormalizationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
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

  test "admit validates and normalizes UiCommand envelopes" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               "command_type" => "open_file",
               "session_id" => "sess-123",
               "correlation_id" => "cor-123",
               "request_id" => "req-123",
               "payload" => %{"path" => "lib/foo.ex"},
               "auth_context" => valid_auth_context()
             })

    assert admitted.envelope_kind == :ui_command
    assert admitted.schema_version == "v1"
    assert admitted.correlation_id == "cor-123"
    assert admitted.request_id == "req-123"
    assert admitted.ui_command.command_type == "open_file"
    assert admitted.ui_command.session_id == "sess-123"
    assert admitted.ui_command.payload == %{"path" => "lib/foo.ex"}
    assert admitted.dispatch_context.session_id == "sess-123"
    assert admitted.dispatch_context.correlation_id == "cor-123"
    assert admitted.dispatch_context.request_id == "req-123"
    assert admitted.auth_context.subject_id == "usr-123"
    assert admitted.orchestrator_envelope.context.envelope_kind == :ui_command
    assert admitted.orchestrator_envelope.context.auth_context.subject_id == "usr-123"
    assert Map.has_key?(admitted, :admitted_at)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.normalization.v1" and
               event.outcome == "accepted" and
               event.envelope_kind == "ui_command"
           end)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.command.received.v1" and
               event.envelope_kind == "ui_command" and
               event.correlation_id == "cor-123" and
               event.request_id == "req-123"
           end)
  end

  test "admit validates and normalizes WidgetUiEventEnvelope payloads" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               type: "unified.button.clicked",
               widget_id: "widget-001",
               correlation_id: "cor-555",
               request_id: "req-555",
               data: %{action: "run"},
               auth_context: valid_auth_context()
             })

    assert admitted.envelope_kind == :widget_ui_event
    assert admitted.schema_version == "v1"
    assert admitted.widget_ui_event.type == "unified.button.clicked"
    assert admitted.widget_ui_event.widget_id == "widget-001"
    assert admitted.widget_ui_event.widget_kind == "unknown_widget"
    assert admitted.widget_ui_event.data == %{action: "run"}
    assert is_binary(admitted.widget_ui_event.timestamp)
    assert admitted.dispatch_context.widget_id == "widget-001"
    assert admitted.orchestrator_envelope.context.envelope_kind == :widget_ui_event
  end

  test "admit rejects malformed UiCommand payloads with schema-path diagnostics" do
    assert {:error,
            %TypedError{
              category: "ingress",
              error_code: "ingress_schema_invalid",
              stage: "ingress_validation"
            } = typed_error} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-123",
               correlation_id: "cor-901",
               request_id: "req-901",
               payload: [:not, :a, :map],
               auth_context: valid_auth_context()
             })

    assert typed_error.details.schema_path == "$.payload"

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.normalization.v1" and
               event.outcome == "rejected" and
               event.error_code == "ingress_schema_invalid"
           end)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.denied.v1" and
               event.error_code == "ingress_schema_invalid" and
               event.policy_context.policy_version == "v1"
           end)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.failure.metric.v1" and
               event.failure_class == "malformed"
           end)
  end

  test "admit rejects missing continuity IDs before dispatch" do
    assert {:error,
            %TypedError{
              category: "ingress",
              error_code: "ingress_continuity_missing",
              stage: "ingress_continuity"
            } = typed_error} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-404",
               payload: %{path: "lib/foo.ex"},
               auth_context: valid_auth_context()
             })

    assert typed_error.details.schema_path == "$.correlation_id"

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.continuity.checked.v1" and
               event.outcome == "rejected" and
               event.error_code == "ingress_continuity_missing"
           end)
  end

  test "admit rejects malformed continuity IDs" do
    assert {:error,
            %TypedError{
              error_code: "ingress_continuity_invalid",
              stage: "ingress_continuity"
            }} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-407",
               correlation_id: "bad id",
               request_id: "req-407",
               payload: %{path: "lib/foo.ex"},
               auth_context: valid_auth_context()
             })
  end

  test "admit emits auth denied diagnostics for missing auth context" do
    assert {:error,
            %TypedError{
              error_code: "ingress_auth_missing",
              stage: "ingress_auth"
            }} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-999",
               correlation_id: "cor-999",
               request_id: "req-999",
               payload: %{path: "lib/foo.ex"}
             })

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.auth.denied.v1" and
               event.error_code == "ingress_auth_missing" and
               event.correlation_id == "cor-999"
           end)
  end

  test "admit normalizes auth context and propagates it to orchestrator envelope" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               command_type: "save_file",
               session_id: "sess-777",
               correlation_id: "cor-777",
               request_id: "req-777",
               payload: %{path: "lib/foo.ex", contents: "hello"},
               auth: %{
                 actor_id: "usr-777",
                 actor_type: "service",
                 roles: ["editor", "  "],
                 scopes: ["files:write"],
                 policy_context: %{policy_version: "v2"},
                 authenticated: true
               }
             })

    assert admitted.auth_context.subject_id == "usr-777"
    assert admitted.auth_context.actor_type == "service"
    assert admitted.auth_context.roles == ["editor"]
    assert admitted.auth_context.scopes == ["files:write"]
    assert admitted.auth_context.policy_context.policy_version == "v2"

    assert admitted.orchestrator_envelope.context.correlation_id == "cor-777"
    assert admitted.orchestrator_envelope.context.request_id == "req-777"
    assert admitted.orchestrator_envelope.context.auth_context.subject_id == "usr-777"
    assert admitted.orchestrator_envelope.context.policy_context.policy_version == "v2"
  end

  test "admit rejects non-map ingress payloads with typed invalid payload errors" do
    assert {:error,
            %TypedError{
              category: "ingress",
              error_code: "ingress_invalid_payload",
              stage: "ingress_validation"
            }} = Substrate.admit("not a map")
  end

  defp valid_auth_context do
    %{
      "subject_id" => "usr-123",
      "roles" => ["editor"],
      "scopes" => ["files:read"],
      "policy_version" => "v1"
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
