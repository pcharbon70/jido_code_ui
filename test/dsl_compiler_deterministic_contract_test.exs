defmodule JidoCodeUi.DslCompilerDeterministicContractTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Contracts.CompileResult
  alias JidoCodeUi.Contracts.UnifiedIurDocument
  alias JidoCodeUi.Contracts.UnifiedUiDslDocument
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Services.DslCompiler
  alias JidoCodeUi.TypedError

  setup do
    defaults = JidoCodeUi.Application.runtime_ready_children()
    :ok = StartupLifecycle.set_expected_children(defaults)

    on_exit(fn ->
      :ok = StartupLifecycle.set_expected_children(defaults)
    end)

    assert_eventually(fn -> StartupLifecycle.ready?() end)
    :ok
  end

  test "compile returns canonical CompileResult with server authority markers" do
    assert {:ok, result} =
             DslCompiler.compile(
               %{dsl_document: canonical_contract_document()},
               correlation_id: "cor-compile-contract",
               request_id: "req-compile-contract"
             )

    assert %CompileResult{} = result
    assert result.compile_authority == "server"
    assert result.dsl_version == "v1"
    assert result.iur_version == "v1"
    assert %UnifiedIurDocument{} = result.iur_document
    assert %UnifiedUiDslDocument{} = result.dsl_document
    assert is_binary(result.iur_hash)
    assert String.length(result.iur_hash) == 64
    assert result.diagnostics == []
  end

  test "equivalent DSL inputs produce identical canonical IUR hash outputs" do
    document_one =
      %{
        dsl_version: "v1",
        root: %{
          type: "layout.stack",
          props: Map.new([{:direction, "vertical"}, {"gap", 8}]),
          attrs: Map.new([{"class", "editor-shell"}, {:z_index, 10}]),
          children: [
            %{
              type: "widget.editor",
              props: Map.new([{"language", "elixir"}, {:theme, "solarized"}])
            }
          ]
        }
      }

    document_two =
      %{
        "root" => %{
          "children" => [
            %{
              "props" => %{"theme" => "solarized", "language" => "elixir"},
              "type" => "widget.editor"
            }
          ],
          "attrs" => %{"z_index" => 10, "class" => "editor-shell"},
          "props" => %{"gap" => 8, "direction" => "vertical"},
          "type" => "layout.stack"
        },
        "dsl_version" => "v1"
      }

    assert {:ok, first_result} =
             DslCompiler.compile(
               %{dsl_document: document_one},
               correlation_id: "cor-compile-hash-1",
               request_id: "req-compile-hash-1"
             )

    assert {:ok, second_result} =
             DslCompiler.compile(
               %{dsl_document: document_two},
               correlation_id: "cor-compile-hash-2",
               request_id: "req-compile-hash-2"
             )

    assert first_result.iur_hash == second_result.iur_hash
    assert first_result.iur_document == second_result.iur_document
  end

  test "diagnostics are deterministic and consistently ordered" do
    request =
      %{
        command: %{
          payload: %{
            path: "lib/ui.ex",
            custom_nodes: ["markdown.preview"]
          }
        }
      }

    opts = [
      feature_flags: %{
        custom_dsl_nodes: true,
        custom_node_allowlist: ["markdown.preview"]
      },
      correlation_id: "cor-compile-diagnostics",
      request_id: "req-compile-diagnostics"
    ]

    assert {:ok, first_result} = DslCompiler.compile(request, opts)
    assert {:ok, second_result} = DslCompiler.compile(request, opts)

    assert first_result.diagnostics == second_result.diagnostics

    assert Enum.map(first_result.diagnostics, & &1["code"]) == [
             "dsl_compat_legacy_payload",
             "dsl_custom_nodes_compiled"
           ]
  end

  test "forced compile failures return typed compile-stage metadata" do
    assert {:error,
            %TypedError{
              category: "compile",
              stage: "dsl_compile",
              error_code: "dsl_compile_failed"
            } = typed_error} =
             DslCompiler.compile(
               %{
                 command: %{
                   payload: %{
                     force_compile_error: true
                   }
                 }
               },
               correlation_id: "cor-compile-fail",
               request_id: "req-compile-fail"
             )

    assert typed_error.details.reason == "forced_failure"
  end

  defp canonical_contract_document do
    %{
      dsl_version: "v1",
      root: %{
        type: "layout.grid",
        props: %{
          columns: 2
        },
        children: [
          %{
            type: "widget.editor",
            props: %{language: "elixir"}
          }
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
