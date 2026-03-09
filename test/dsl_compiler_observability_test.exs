defmodule JidoCodeUi.DslCompilerObservabilityTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Services.DslCompiler
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

  test "compile emits lifecycle events for successful and failed compile paths" do
    assert {:ok, _result} =
             DslCompiler.compile(
               %{dsl_document: valid_dsl_document()},
               correlation_id: "cor-obs-success",
               request_id: "req-obs-success"
             )

    invalid = put_in(valid_dsl_document(), [:dsl_version], "v9")

    assert {:error, %TypedError{error_code: "dsl_schema_incompatible"}} =
             DslCompiler.compile(
               %{dsl_document: invalid},
               correlation_id: "cor-obs-failure",
               request_id: "req-obs-failure"
             )

    events = Telemetry.recent_events(200)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-obs-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.completed.v1" and
               event.correlation_id == "cor-obs-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-obs-failure"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.failed.v1" and
               event.correlation_id == "cor-obs-failure" and
               event.error_code == "dsl_schema_incompatible"
           end)
  end

  test "compile emits latency, throughput, failure, and parity diagnostics metrics" do
    unique_type = "widget.terminal." <> Integer.to_string(System.unique_integer([:positive]))

    dsl_document = %{
      dsl_version: "v1",
      root: %{
        type: "layout.stack",
        children: [
          %{type: unique_type}
        ]
      }
    }

    assert {:ok, _first} =
             DslCompiler.compile(
               %{dsl_document: dsl_document},
               correlation_id: "cor-obs-metrics",
               request_id: "req-obs-metrics"
             )

    assert {:ok, _second} =
             DslCompiler.compile(
               %{dsl_document: dsl_document},
               correlation_id: "cor-obs-metrics",
               request_id: "req-obs-metrics"
             )

    invalid = put_in(dsl_document, [:dsl_version], "v99")

    assert {:error, %TypedError{error_code: "dsl_schema_incompatible"}} =
             DslCompiler.compile(
               %{dsl_document: invalid},
               correlation_id: "cor-obs-metrics-fail",
               request_id: "req-obs-metrics-fail"
             )

    events = Telemetry.recent_events(400)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.metric.v1" and
               event.metric == "compile_latency_ms" and
               event.outcome == "success" and
               event.complexity_class in ["small", "medium", "large"]
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.metric.v1" and
               event.metric == "compile_total" and
               event.outcome == "failure" and
               event.error_category == "compile" and
               event.error_code == "dsl_schema_incompatible"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.determinism.parity.v1" and
               event.correlation_id == "cor-obs-metrics" and
               event.status in ["baseline", "match"]
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.determinism.parity.v1" and
               event.correlation_id == "cor-obs-metrics" and
               event.status == "match"
           end)
  end

  defp valid_dsl_document do
    %{
      dsl_version: "v1",
      root: %{
        type: "layout.stack",
        props: %{direction: "vertical"},
        children: [
          %{type: "widget.editor"}
        ]
      }
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
