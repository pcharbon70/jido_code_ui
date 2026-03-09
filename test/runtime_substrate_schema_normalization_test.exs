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
               "payload" => %{"path" => "lib/foo.ex"}
             })

    assert admitted.envelope_kind == :ui_command
    assert admitted.schema_version == "v1"
    assert admitted.correlation_id == "cor-123"
    assert admitted.request_id == "req-123"
    assert admitted.ui_command.command_type == "open_file"
    assert admitted.ui_command.session_id == "sess-123"
    assert admitted.ui_command.payload == %{"path" => "lib/foo.ex"}
    assert admitted.dispatch_context.session_id == "sess-123"
    assert Map.has_key?(admitted, :admitted_at)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.normalization.v1" and
               event.outcome == "accepted" and
               event.envelope_kind == "ui_command"
           end)
  end

  test "admit validates and normalizes WidgetUiEventEnvelope payloads" do
    assert {:ok, admitted} =
             Substrate.admit(%{
               type: "unified.button.clicked",
               widget_id: "widget-001",
               correlation_id: "cor-555",
               request_id: "req-555",
               data: %{action: "run"}
             })

    assert admitted.envelope_kind == :widget_ui_event
    assert admitted.schema_version == "v1"
    assert admitted.widget_ui_event.type == "unified.button.clicked"
    assert admitted.widget_ui_event.widget_id == "widget-001"
    assert admitted.widget_ui_event.widget_kind == "unknown_widget"
    assert admitted.widget_ui_event.data == %{action: "run"}
    assert is_binary(admitted.widget_ui_event.timestamp)
    assert admitted.dispatch_context.widget_id == "widget-001"
  end

  test "admit rejects malformed UiCommand payloads with schema-path diagnostics" do
    assert {:error,
            %TypedError{
              category: "validation",
              error_code: "ingress_schema_invalid",
              stage: "ingress_validation"
            } = typed_error} =
             Substrate.admit(%{
               command_type: "open_file",
               session_id: "sess-123",
               correlation_id: "cor-901",
               request_id: "req-901",
               payload: [:not, :a, :map]
             })

    assert typed_error.details.schema_path == "$.payload"

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.ingress.normalization.v1" and
               event.outcome == "rejected" and
               event.error_code == "ingress_schema_invalid"
           end)
  end

  test "admit rejects non-map ingress payloads with typed invalid payload errors" do
    assert {:error,
            %TypedError{
              category: "validation",
              error_code: "ingress_invalid_payload",
              stage: "ingress_validation"
            }} = Substrate.admit("not a map")
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
