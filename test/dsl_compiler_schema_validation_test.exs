defmodule JidoCodeUi.DslCompilerSchemaValidationTest do
  use ExUnit.Case, async: false

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

  test "compile validates required DSL schema fields before execution" do
    assert {:ok, result} =
             DslCompiler.compile(
               %{
                 dsl_document: valid_dsl_document()
               },
               correlation_id: "cor-dsl-valid",
               request_id: "req-dsl-valid"
             )

    assert result.compile_authority == "server"
    assert result.dsl_version == "v1"
    assert is_map(result.dsl_document)
  end

  test "compile rejects unsupported DSL schema versions with typed compatibility errors" do
    invalid_version_document = put_in(valid_dsl_document(), [:dsl_version], "v9")

    assert {:error,
            %TypedError{
              category: "compile",
              stage: "dsl_validation",
              error_code: "dsl_schema_incompatible"
            } = typed_error} =
             DslCompiler.compile(
               %{dsl_document: invalid_version_document},
               correlation_id: "cor-dsl-version",
               request_id: "req-dsl-version"
             )

    assert typed_error.details.schema_path == "$.dsl_version"
    assert typed_error.details.received == "v9"
    assert "v1" in typed_error.details.supported_versions
  end

  test "compile rejects malformed node structure with schema-path diagnostics" do
    malformed_document = put_in(valid_dsl_document(), [:root, :children], "not-a-list")

    assert {:error,
            %TypedError{
              category: "compile",
              stage: "dsl_validation",
              error_code: "dsl_schema_invalid"
            } = typed_error} =
             DslCompiler.compile(
               %{dsl_document: malformed_document},
               correlation_id: "cor-dsl-structure",
               request_id: "req-dsl-structure"
             )

    assert typed_error.details.schema_path == "$.root.children"
  end

  test "compile enforces custom-node feature flags and allowlist compatibility" do
    dsl_with_custom_node =
      put_in(valid_dsl_document(), [:root, :children], [
        %{
          type: "custom.markdown.preview",
          props: %{"source" => "README.md"}
        }
      ])

    assert {:error, %TypedError{error_code: "dsl_custom_node_disallowed"}} =
             DslCompiler.compile(
               %{dsl_document: dsl_with_custom_node},
               correlation_id: "cor-dsl-custom-flag-off",
               request_id: "req-dsl-custom-flag-off"
             )

    assert {:error, %TypedError{error_code: "dsl_custom_node_incompatible"}} =
             DslCompiler.compile(
               %{dsl_document: dsl_with_custom_node},
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["diagram.mermaid"]
               },
               correlation_id: "cor-dsl-custom-allowlist-deny",
               request_id: "req-dsl-custom-allowlist-deny"
             )

    assert {:ok, compiled} =
             DslCompiler.compile(
               %{dsl_document: dsl_with_custom_node},
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["markdown.preview"]
               },
               correlation_id: "cor-dsl-custom-allow",
               request_id: "req-dsl-custom-allow"
             )

    assert compiled.compile_authority == "server"
  end

  test "compile treats policy decision feature flags as authoritative over conflicting opts" do
    dsl_with_custom_node =
      put_in(valid_dsl_document(), [:root, :children], [
        %{
          type: "custom.markdown.preview",
          props: %{"source" => "README.md"}
        }
      ])

    assert {:error, %TypedError{error_code: "dsl_custom_node_disallowed"}} =
             DslCompiler.compile(
               %{
                 dsl_document: dsl_with_custom_node,
                 policy_decision: %{
                   policy_version: "v9",
                   feature_flags: %{custom_dsl_nodes: false}
                 }
               },
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["markdown.preview"]
               },
               correlation_id: "cor-dsl-policy-authority",
               request_id: "req-dsl-policy-authority"
             )
  end

  test "compile treats explicit nil policy decision feature flags as authoritative" do
    dsl_with_custom_node =
      put_in(valid_dsl_document(), [:root, :children], [
        %{
          type: "custom.markdown.preview",
          props: %{"source" => "README.md"}
        }
      ])

    assert {:error, %TypedError{error_code: "dsl_custom_node_disallowed"}} =
             DslCompiler.compile(
               %{
                 dsl_document: dsl_with_custom_node,
                 policy_decision: %{
                   policy_version: "v9",
                   feature_flags: nil
                 }
               },
               feature_flags: %{
                 custom_dsl_nodes: true,
                 custom_node_allowlist: ["markdown.preview"]
               },
               correlation_id: "cor-dsl-policy-authority-nil",
               request_id: "req-dsl-policy-authority-nil"
             )
  end

  test "compile treats policy decision policy_version as authoritative over opts" do
    assert {:ok, compiled} =
             DslCompiler.compile(
               %{
                 dsl_document: valid_dsl_document(),
                 policy_decision: %{
                   policy_version: "v9",
                   feature_flags: %{}
                 }
               },
               policy_version: "v1",
               correlation_id: "cor-dsl-policy-version-authority",
               request_id: "req-dsl-policy-version-authority"
             )

    assert compiled.iur_document.metadata["policy_version"] == "v9"
  end

  test "compile treats explicit nil policy decision policy_version as authoritative" do
    assert {:ok, compiled} =
             DslCompiler.compile(
               %{
                 dsl_document: valid_dsl_document(),
                 policy_decision: %{
                   policy_version: nil,
                   feature_flags: %{}
                 }
               },
               policy_version: "v9",
               correlation_id: "cor-dsl-policy-version-authority-nil",
               request_id: "req-dsl-policy-version-authority-nil"
             )

    assert compiled.iur_document.metadata["policy_version"] == "v1"
  end

  defp valid_dsl_document do
    %{
      dsl_version: "v1",
      root: %{
        type: "layout.stack",
        props: %{"direction" => "vertical"},
        children: [
          %{
            type: "widget.editor",
            props: %{"language" => "elixir"}
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
