defmodule JidoCodeUi.EventProjectionLoopTest do
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

  test "project_widget_event maps browser payload into WidgetUiEventEnvelope with render continuity" do
    render_result = render_result_fixture()
    widget_id = button_widget_id(render_result)

    assert {:ok, projected_event} =
             EventProjectionLoop.project_widget_event(
               render_result,
               %{
                 type: "unified.button.clicked",
                 widget_id: widget_id,
                 data: %{action: "run"}
               },
               auth_context: editor_auth("v2")
             )

    assert projected_event.type == "unified.button.clicked"
    assert projected_event.widget_id == widget_id
    assert projected_event.correlation_id == render_result.continuity.correlation_id
    assert projected_event.request_id == render_result.continuity.request_id
    assert projected_event.session_id == render_result.continuity.session_id
    assert projected_event.route_key == render_result.continuity.route_key
    assert projected_event.render_token == render_result.continuity.render_token
    assert projected_event.auth_context.subject_id == "usr-event-editor"
    assert projected_event.data.render_token == render_result.continuity.render_token

    assert Enum.any?(Telemetry.recent_events(80), fn event ->
             event.event_name == "ui.event_projection.projected.v1" and
               event.correlation_id == render_result.continuity.correlation_id and
               event.widget_id == widget_id
           end)
  end

  test "project_widget_event returns typed projection errors for invalid event conversion" do
    render_result = render_result_fixture()

    assert {:error,
            %TypedError{
              category: "projection",
              stage: "event_projection_validation",
              error_code: "event_projection_invalid_event"
            } = typed_error} =
             EventProjectionLoop.project_widget_event(
               render_result,
               %{type: "unified.button.clicked", data: %{action: "run"}},
               auth_context: editor_auth("v1")
             )

    assert typed_error.details.schema_path == "$.widget_id"
  end

  test "round_trip admits projected events and executes widget-event orchestration paths" do
    render_result = render_result_fixture()
    widget_id = button_widget_id(render_result)

    assert {:ok, result} =
             EventProjectionLoop.round_trip(
               render_result,
               %{
                 type: "unified.button.clicked",
                 widget_id: widget_id,
                 data: %{action: "run"}
               },
               auth_context: editor_auth("v3")
             )

    assert result.projected_event.widget_id == widget_id
    assert result.admitted_event.envelope_kind == :widget_ui_event

    assert result.admitted_event.dispatch_context.session_id ==
             render_result.continuity.session_id

    assert result.admitted_event.dispatch_context.route_key == render_result.continuity.route_key

    assert result.orchestration.status == :ok
    assert result.orchestration.envelope_kind == :widget_ui_event
    assert result.orchestration.stage_trace == [:validate, :policy, :compile, :session, :render]

    assert result.orchestration.continuity.correlation_id ==
             render_result.continuity.correlation_id

    assert result.orchestration.continuity.request_id == render_result.continuity.request_id
    assert result.orchestration.compile.dsl_document.root.props.type == "unified.button.clicked"
    assert result.orchestration.compile.dsl_document.root.props.widget_id == widget_id

    assert result.orchestration.compile.dsl_document.root.props.route_key ==
             render_result.continuity.route_key

    events = Telemetry.recent_events(200)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.event_projection.admitted.v1" and
               event.correlation_id == render_result.continuity.correlation_id and
               event.envelope_kind == "widget_ui_event"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.render.event.round_trip.v1" and
               event.outcome == "success" and
               event.correlation_id == render_result.continuity.correlation_id
           end)
  end

  defp render_result_fixture do
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
        correlation_id: "cor-event-loop-compile",
        request_id: "req-event-loop-compile"
      )

    {:ok, render_result} =
      IurRenderer.render(
        %{
          compile_result: compile_result,
          route_key: "route-event-loop",
          session_snapshot: %{session_id: "sess-event-loop"}
        },
        correlation_id: "cor-event-loop",
        request_id: "req-event-loop"
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
      subject_id: "usr-event-editor",
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
