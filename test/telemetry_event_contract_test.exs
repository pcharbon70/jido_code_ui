defmodule JidoCodeUi.TelemetryEventContractTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry

  setup do
    :ok = Telemetry.reset_events()

    on_exit(fn ->
      :ok = Telemetry.reset_events()
    end)

    :ok
  end

  test "ui events get continuity fallback and event schema version markers" do
    :ok = Telemetry.emit("ui.dsl.compile.started.v1", %{route_key: "route-contract"})

    [event] = Telemetry.recent_events(1)

    assert event.event_name == "ui.dsl.compile.started.v1"
    assert event.event_schema_version == "v1"
    assert String.starts_with?(event.correlation_id, "cor-")
    assert String.starts_with?(event.request_id, "req-")
    assert event.route_key == "route-contract"
  end

  test "missing required join keys emit observability validation diagnostics" do
    :ok = Telemetry.emit("ui.command.received.v1", %{envelope_kind: "ui_command"})

    events = Telemetry.recent_events(20)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.telemetry.validation.failed.v1" and
               event.source_event == "ui.command.received.v1" and
               event.error_code == "observability_event_missing_keys" and
               "session_id" in event.missing_keys
           end)
  end

  test "non-ui telemetry events are not forced through ui join-key contracts" do
    :ok = Telemetry.emit("runtime.startup.sample", %{child: :runtime_substrate})

    events = Telemetry.recent_events(10)

    startup_event =
      Enum.find(events, fn event -> event.event_name == "runtime.startup.sample" end)

    assert startup_event != nil
    assert startup_event.child == :runtime_substrate

    refute Enum.any?(events, fn event ->
             event.event_name == "ui.telemetry.validation.failed.v1" and
               event.source_event == "runtime.startup.sample"
           end)
  end
end
