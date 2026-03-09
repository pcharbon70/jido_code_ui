defmodule JidoCodeUi.IurRendererProjectionContractTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Services.DslCompiler
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

  test "render maps canonical IUR into deterministic web-ui projection with continuity metadata" do
    compile_result = compile_result_fixture()

    assert {:ok, rendered} =
             IurRenderer.render(
               %{
                 compile_result: compile_result,
                 session_snapshot: %{session_id: "sess-render-projection"},
                 route_key: "route-render-projection"
               },
               correlation_id: "cor-render-projection",
               request_id: "req-render-projection"
             )

    assert rendered.rendered == true
    assert rendered.projection.schema_version == "v1"
    assert rendered.projection.route_key == "route-render-projection"
    assert rendered.projection.iur_hash == compile_result.iur_hash
    assert is_map(rendered.projection.root)
    assert is_list(rendered.projection.widgets)
    assert rendered.continuity.correlation_id == "cor-render-projection"
    assert rendered.continuity.request_id == "req-render-projection"
    assert rendered.continuity.session_id == "sess-render-projection"
    assert rendered.event_projection.schema_version == "v1"
    assert rendered.event_projection.session_id == "sess-render-projection"
    assert String.starts_with?(rendered.continuity.render_token, "rnd-")
  end

  test "render returns typed invalid-IUR failures for incompatible IUR versions" do
    compile_result = compile_result_fixture() |> Map.put(:iur_version, "v9")

    assert {:error,
            %TypedError{
              category: "render",
              stage: "iur_render_validation",
              error_code: "iur_invalid_document"
            }} =
             IurRenderer.render(
               %{compile_result: compile_result, route_key: "route-render-invalid"},
               correlation_id: "cor-render-invalid",
               request_id: "req-render-invalid"
             )
  end

  test "render normalizes adapter failures and emits failure telemetry with continuity IDs" do
    compile_result =
      compile_result_fixture()
      |> Map.put(:dsl_document, %{root: %{props: %{force_render_error: true}}})

    assert {:error,
            %TypedError{
              category: "render",
              stage: "iur_render_adapter",
              error_code: "iur_adapter_failed"
            }} =
             IurRenderer.render(
               %{compile_result: compile_result, route_key: "route-render-failure"},
               correlation_id: "cor-render-failure",
               request_id: "req-render-failure"
             )

    assert Enum.any?(Telemetry.recent_events(50), fn event ->
             event.event_name == "ui.iur.render.failed.v1" and
               event.error_code == "iur_adapter_failed" and
               event.error_classification == "adapter_failure" and
               event.correlation_id == "cor-render-failure" and
               event.request_id == "req-render-failure"
           end)
  end

  defp compile_result_fixture do
    {:ok, result} =
      DslCompiler.compile(
        %{
          dsl_document: %{
            dsl_version: "v1",
            root: %{
              type: "layout.stack",
              props: %{direction: "vertical"},
              children: [
                %{type: "widget.editor", props: %{language: "elixir"}}
              ]
            }
          }
        },
        correlation_id: "cor-render-compile",
        request_id: "req-render-compile"
      )

    result
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
