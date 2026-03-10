defmodule JidoCodeUi.IurRenderEventRoundTripIntegrationTest do
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

  test "compile-render-event round trip remains deterministic and preserves continuity metadata" do
    compile_result = compile_result_fixture()

    render_one =
      render_fixture(
        compile_result,
        "cor-roundtrip-deterministic",
        "req-roundtrip-deterministic",
        "route-roundtrip-deterministic",
        "sess-roundtrip-deterministic"
      )

    render_two =
      render_fixture(
        compile_result,
        "cor-roundtrip-deterministic",
        "req-roundtrip-deterministic",
        "route-roundtrip-deterministic",
        "sess-roundtrip-deterministic"
      )

    assert render_one.projection == render_two.projection
    assert render_one.continuity.render_token == render_two.continuity.render_token

    widget_id = button_widget_id(render_one)

    assert {:ok, round_trip_result} =
             EventProjectionLoop.round_trip(
               render_one,
               %{
                 type: "unified.button.clicked",
                 widget_id: widget_id,
                 data: %{action: "run"}
               },
               auth_context: editor_auth("v4")
             )

    assert round_trip_result.projected_event.widget_id == widget_id
    assert round_trip_result.admitted_event.envelope_kind == :widget_ui_event
    assert round_trip_result.orchestration.envelope_kind == :widget_ui_event

    assert round_trip_result.orchestration.stage_trace == [
             :validate,
             :policy,
             :compile,
             :session,
             :render
           ]

    assert round_trip_result.orchestration.render.rendered == true

    assert round_trip_result.projected_event.correlation_id ==
             render_one.continuity.correlation_id

    assert round_trip_result.projected_event.request_id == render_one.continuity.request_id
    assert round_trip_result.projected_event.session_id == render_one.continuity.session_id
    assert round_trip_result.projected_event.route_key == render_one.continuity.route_key
    assert round_trip_result.projected_event.render_token == render_one.continuity.render_token

    assert round_trip_result.admitted_event.correlation_id == render_one.continuity.correlation_id
    assert round_trip_result.admitted_event.request_id == render_one.continuity.request_id

    assert round_trip_result.admitted_event.dispatch_context.session_id ==
             render_one.continuity.session_id

    assert round_trip_result.orchestration.continuity.correlation_id ==
             render_one.continuity.correlation_id

    assert round_trip_result.orchestration.continuity.request_id ==
             render_one.continuity.request_id

    assert round_trip_result.orchestration.continuity.session_id ==
             render_one.continuity.session_id
  end

  test "render failures normalize typed errors and emit lifecycle plus metrics telemetry coverage" do
    compile_result = compile_result_fixture()

    assert {:error,
            %TypedError{
              category: "render",
              stage: "iur_render_validation",
              error_code: "iur_invalid_document"
            }} =
             IurRenderer.render(
               %{
                 compile_result: Map.put(compile_result, :iur_version, "v9"),
                 route_key: "route-invalid-iur"
               },
               correlation_id: "cor-invalid-iur",
               request_id: "req-invalid-iur"
             )

    success_render =
      render_fixture(
        compile_result,
        "cor-lifecycle-success",
        "req-lifecycle-success",
        "route-lifecycle-success",
        "sess-lifecycle-success"
      )

    failing_compile_result =
      compile_result
      |> Map.put(:dsl_document, %{root: %{props: %{force_render_error: true}}})

    assert {:error,
            %TypedError{
              category: "render",
              stage: "iur_render_adapter",
              error_code: "iur_adapter_failed"
            }} =
             IurRenderer.render(
               %{compile_result: failing_compile_result, route_key: "route-lifecycle-failure"},
               correlation_id: "cor-lifecycle-failure",
               request_id: "req-lifecycle-failure"
             )

    assert {:ok, _round_trip_result} =
             EventProjectionLoop.round_trip(
               success_render,
               %{
                 type: "unified.button.clicked",
                 widget_id: button_widget_id(success_render),
                 data: %{action: "run"}
               },
               auth_context: editor_auth("v5")
             )

    events = Telemetry.recent_events(300)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.started.v1" and
               event.correlation_id == "cor-lifecycle-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.completed.v1" and
               event.correlation_id == "cor-lifecycle-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.failed.v1" and
               event.correlation_id == "cor-lifecycle-failure" and
               event.error_code == "iur_adapter_failed"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_latency_ms" and
               event.outcome == "success" and
               event.correlation_id == "cor-lifecycle-success"
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
               event.outcome == "success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_total" and
               event.outcome == "failure"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.iur.render.metric.v1" and
               event.metric == "render_event_round_trip_latency_ms" and
               event.outcome == "success" and
               event.correlation_id == "cor-lifecycle-success"
           end)
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
        correlation_id: "cor-roundtrip-compile",
        request_id: "req-roundtrip-compile"
      )

    compile_result
  end

  defp render_fixture(compile_result, correlation_id, request_id, route_key, session_id) do
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
      subject_id: "usr-roundtrip-editor",
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
