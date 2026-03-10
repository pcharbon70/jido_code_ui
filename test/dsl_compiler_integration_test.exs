defmodule JidoCodeUi.DslCompilerIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Services.DslCompiler
  alias JidoCodeUi.TypedError

  @moduletag :integration

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

  test "hash parity and version compatibility integration scenarios" do
    dsl_one =
      %{
        dsl_version: "v1",
        root: %{
          type: "layout.stack",
          props: %{"gap" => 8, "direction" => "vertical"},
          children: [
            %{
              type: "widget.editor",
              props: %{"language" => "elixir"}
            }
          ]
        }
      }

    dsl_two =
      %{
        "root" => %{
          "children" => [%{"props" => %{"language" => "elixir"}, "type" => "widget.editor"}],
          "type" => "layout.stack",
          "props" => %{"direction" => "vertical", "gap" => 8}
        },
        "dsl_version" => "v1"
      }

    assert {:ok, first} =
             DslCompiler.compile(
               %{dsl_document: dsl_one},
               correlation_id: "cor-int-compile-hash-1",
               request_id: "req-int-compile-hash-1"
             )

    assert {:ok, second} =
             DslCompiler.compile(
               %{dsl_document: dsl_two},
               correlation_id: "cor-int-compile-hash-2",
               request_id: "req-int-compile-hash-2"
             )

    assert first.iur_hash == second.iur_hash

    assert {:error,
            %TypedError{
              category: "compile",
              stage: "dsl_validation",
              error_code: "dsl_schema_incompatible"
            }} =
             DslCompiler.compile(
               %{dsl_document: put_in(dsl_one, [:dsl_version], "v99")},
               correlation_id: "cor-int-compile-version",
               request_id: "req-int-compile-version"
             )

    custom_node_document =
      put_in(dsl_one, [:root, :children], [
        %{type: "custom.markdown.preview"}
      ])

    assert {:error, %TypedError{error_code: "dsl_custom_node_disallowed"}} =
             DslCompiler.compile(
               %{dsl_document: custom_node_document},
               correlation_id: "cor-int-compile-custom-deny",
               request_id: "req-int-compile-custom-deny"
             )

    assert {:ok, custom_allowed} =
             DslCompiler.compile(
               %{dsl_document: custom_node_document},
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["markdown.preview"]
               },
               correlation_id: "cor-int-compile-custom-allow",
               request_id: "req-int-compile-custom-allow"
             )

    assert custom_allowed.compile_authority == "server"
    assert custom_allowed.iur_version == "v1"
  end

  test "compile failure and observability integration scenarios" do
    assert {:error,
            %TypedError{
              category: "compile",
              stage: "dsl_compile",
              error_code: "dsl_compile_failed"
            }} =
             DslCompiler.compile(
               %{command: %{payload: %{force_compile_error: true}}},
               correlation_id: "cor-int-compile-failure",
               request_id: "req-int-compile-failure"
             )

    assert {:ok, _success} =
             DslCompiler.compile(
               %{dsl_document: success_document()},
               correlation_id: "cor-int-compile-success",
               request_id: "req-int-compile-success"
             )

    events = Telemetry.recent_events(300)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-int-compile-failure"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.failed.v1" and
               event.correlation_id == "cor-int-compile-failure" and
               event.error_code == "dsl_compile_failed"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.started.v1" and
               event.correlation_id == "cor-int-compile-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.completed.v1" and
               event.correlation_id == "cor-int-compile-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.metric.v1" and
               event.metric == "compile_latency_ms" and
               event.outcome == "success" and
               event.correlation_id == "cor-int-compile-success"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.dsl.compile.metric.v1" and
               event.metric == "compile_total" and
               event.outcome == "failure" and
               event.error_code == "dsl_compile_failed" and
               event.correlation_id == "cor-int-compile-failure"
           end)
  end

  test "compile honors explicit force_error false when conflicting string fallback exists" do
    assert {:ok, compile_result} =
             DslCompiler.compile(
               %{
                 "force_error" => true,
                 dsl_document: success_document(),
                 force_error: false
               },
               correlation_id: "cor-int-compile-force-error-precedence",
               request_id: "req-int-compile-force-error-precedence"
             )

    assert compile_result.compile_authority == "server"
  end

  defp success_document do
    %{
      dsl_version: "v1",
      root: %{
        type: "layout.stack",
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
