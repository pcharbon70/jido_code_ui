defmodule JidoCodeUi.IurRendererObservabilityTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Services.DslCompiler
  alias JidoCodeUi.Services.EventProjectionLoop
  alias JidoCodeUi.Services.IurRenderer
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

  test "render emits started/completed lifecycle events and success metrics by payload class" do
    compile_result = compile_result_fixture()

    assert {:ok, rendered} =
             IurRenderer.render(
               %{
                 compile_result: compile_result,
                 route_key: "route-render-observability",
                 session_snapshot: %{session_id: "sess-render-observability"}
               },
               correlation_id: "cor-render-observability",
               request_id: "req-render-observability"
             )

    assert rendered.render_metadata.payload_class == "small"

    events = Telemetry.recent_events(160)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.started.v1" and
               event.correlation_id == "cor-render-observability" and
               event.route_key == "route-render-observability"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.completed.v1" and
               event.correlation_id == "cor-render-observability" and
               event.payload_class == "small"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_latency_ms" and
               event.outcome == "success" and
               event.payload_class == "small"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_total" and
               event.outcome == "success"
           end)
  end

  test "render emits failed lifecycle events and failure metrics with typed error classification" do
    compile_result =
      compile_result_fixture()
      |> Map.put(:dsl_document, %{root: %{props: %{force_render_error: true}}})

    assert {:error,
            %TypedError{
              error_code: "iur_adapter_failed",
              category: "render",
              stage: "iur_render_adapter"
            }} =
             IurRenderer.render(
               %{
                 compile_result: compile_result,
                 route_key: "route-render-observability-fail"
               },
               correlation_id: "cor-render-observability-fail",
               request_id: "req-render-observability-fail"
             )

    events = Telemetry.recent_events(200)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.failed.v1" and
               event.error_code == "iur_adapter_failed" and
               event.error_classification == "adapter_failure" and
               event.correlation_id == "cor-render-observability-fail"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_latency_ms" and
               event.outcome == "failure" and
               event.error_code == "iur_adapter_failed"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_total" and
               event.outcome == "failure" and
               event.error_code == "iur_adapter_failed"
           end)
  end

  test "render-event round trip emits round-trip latency metric across compile-render-event boundaries" do
    render_result =
      render_result_fixture(
        "cor-render-roundtrip",
        "req-render-roundtrip",
        "route-render-roundtrip",
        "sess-render-roundtrip"
      )

    widget_id = button_widget_id(render_result)

    assert {:ok, _result} =
             EventProjectionLoop.round_trip(
               render_result,
               %{
                 type: "unified.button.clicked",
                 widget_id: widget_id,
                 data: %{action: "run"}
               },
               auth_context: editor_auth("v2")
             )

    assert Enum.any?(Telemetry.recent_events(200), fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_event_round_trip_latency_ms" and
               event.outcome == "success" and
               event.correlation_id == "cor-render-roundtrip"
           end)
  end

  defp render_result_fixture(correlation_id, request_id, route_key, session_id) do
    compile_result = compile_result_fixture()

    {:ok, render_result} =
      IurRenderer.render(
        %{
          compile_result: compile_result,
          route_key: route_key,
          session_snapshot: %{session_id: session_id}
        },
        correlation_id: correlation_id,
        request_id: request_id
      )

    render_result
  end

  defp compile_result_fixture do
    {:ok, compile_result} =
      DslCompiler.compile(
        %{
          dsl_document: %{
            dsl_version: "v1",
            root: %{
              type: "layout.stack",
              props: %{direction: "vertical"},
              children: [
                %{type: "widget.button", props: %{action: "run", label: "Run"}}
              ]
            }
          }
        },
        correlation_id: "cor-render-observability-compile",
        request_id: "req-render-observability-compile"
      )

    compile_result
  end

  defp button_widget_id(render_result) do
    render_result.projection.widgets
    |> Enum.find(fn widget -> widget.widget_kind == "widget.button" end)
    |> case do
      %{widget_id: widget_id} -> widget_id
      _ -> render_result.projection.root.widget_id
    end
  end

  defp editor_auth(policy_version) do
    %{
      subject_id: "usr-render-observability",
      roles: ["editor"],
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
