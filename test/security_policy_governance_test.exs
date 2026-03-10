defmodule JidoCodeUi.SecurityPolicyGovernanceTest do
  use ExUnit.Case, async: true

  alias JidoCodeUi.Contracts.UiCommand
  alias JidoCodeUi.Contracts.WidgetUiEventEnvelope
  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Security.Policy
  alias JidoCodeUi.TypedError

  setup do
    Telemetry.reset_events()

    on_exit(fn ->
      :ok = Telemetry.reset_events()
    end)

    :ok
  end

  test "authorize returns allow with policy-versioned request shape" do
    context = %{
      correlation_id: "cor-pol-allow",
      request_id: "req-pol-allow",
      auth_context: %{
        subject_id: "usr-editor",
        roles: ["editor"],
        authenticated: true
      },
      policy_context: %{policy_version: "v2"}
    }

    command =
      UiCommand.new(%{
        command_type: "open_file",
        payload: %{path: "lib/app.ex"}
      })

    assert {:ok, decision} = Policy.authorize(context, command)
    assert decision.decision == :allow
    assert decision.policy_version == "v2"
    assert decision.request.actor.subject_id == "usr-editor"
    assert decision.request.command.command_type == "open_file"
    assert decision.request.continuity.correlation_id == "cor-pol-allow"
    assert decision.request.continuity.request_id == "req-pol-allow"
  end

  test "authorize denies unauthorized mutating commands with typed outcomes" do
    context = %{
      correlation_id: "cor-pol-deny",
      request_id: "req-pol-deny",
      auth_context: %{
        subject_id: "usr-viewer",
        roles: ["viewer"],
        authenticated: true
      },
      policy_context: %{policy_version: "v3"}
    }

    command =
      UiCommand.new(%{
        command_type: "save_file",
        payload: %{path: "lib/app.ex"}
      })

    assert {:error,
            %TypedError{
              category: "policy",
              stage: "policy_authorization",
              error_code: "policy_mutation_denied"
            } = typed_error} = Policy.authorize(context, command)

    assert typed_error.details.policy_version == "v3"
    assert typed_error.correlation_id == "cor-pol-deny"
    assert typed_error.request_id == "req-pol-deny"
  end

  test "authorize denies custom nodes when feature flag is disabled and emits policy telemetry" do
    context = %{
      correlation_id: "cor-pol-custom-deny",
      request_id: "req-pol-custom-deny",
      auth_context: %{
        subject_id: "usr-editor",
        roles: ["editor"],
        authenticated: true
      },
      policy_context: %{policy_version: "v1", feature_flags: %{custom_dsl_nodes: false}}
    }

    command =
      UiCommand.new(%{
        command_type: "save_file",
        payload: %{custom_nodes: ["markdown.preview"]}
      })

    assert {:error, %TypedError{error_code: "policy_custom_node_denied"}} =
             Policy.authorize(context, command)

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.policy.custom_node.deny.v1" and
               event.policy_version == "v1" and
               event.custom_nodes == ["markdown.preview"]
           end)
  end

  test "authorize honors explicit authenticated false over conflicting string-key fallback" do
    context = %{
      correlation_id: "cor-pol-auth-false-precedence",
      request_id: "req-pol-auth-false-precedence",
      auth_context: %{
        "authenticated" => true,
        subject_id: "usr-editor",
        roles: ["editor"],
        authenticated: false
      },
      policy_context: %{policy_version: "v1"}
    }

    command =
      UiCommand.new(%{
        command_type: "open_file",
        payload: %{path: "lib/app.ex"}
      })

    assert {:error, %TypedError{error_code: "policy_auth_required"}} =
             Policy.authorize(context, command)
  end

  test "authorize honors explicit custom-node flag false over conflicting string-key fallback" do
    context = %{
      correlation_id: "cor-pol-custom-flag-precedence",
      request_id: "req-pol-custom-flag-precedence",
      auth_context: %{
        subject_id: "svc-orchestrator",
        actor_type: "service",
        roles: ["editor"],
        authenticated: true
      },
      policy_context: %{
        policy_version: "v1",
        feature_flags: %{
          "custom_dsl_nodes" => true,
          custom_dsl_nodes: false,
          custom_node_allowlist: ["markdown.preview"]
        }
      }
    }

    command =
      UiCommand.new(%{
        command_type: "save_file",
        payload: %{custom_nodes: ["markdown.preview"]}
      })

    assert {:error, %TypedError{error_code: "policy_custom_node_denied"}} =
             Policy.authorize(context, command)
  end

  test "authorize allows custom nodes when flag and allowlist permit execution" do
    context = %{
      correlation_id: "cor-pol-custom-allow",
      request_id: "req-pol-custom-allow",
      auth_context: %{
        subject_id: "svc-orchestrator",
        actor_type: "service",
        roles: ["viewer"],
        authenticated: true
      },
      policy_context: %{
        policy_version: "v4",
        feature_flags: %{
          custom_dsl_nodes: true,
          custom_node_allowlist: ["markdown.preview", "diagram.mermaid"]
        }
      }
    }

    command =
      UiCommand.new(%{
        command_type: "save_file",
        payload: %{custom_nodes: ["markdown.preview"]}
      })

    assert {:ok, decision} = Policy.authorize(context, command)
    assert decision.policy_version == "v4"
    assert decision.metadata.custom_nodes == ["markdown.preview"]

    assert Enum.any?(Telemetry.recent_events(20), fn event ->
             event.event_name == "ui.policy.custom_node.allow.v1" and
               event.policy_version == "v4" and
               event.custom_nodes == ["markdown.preview"]
           end)
  end

  test "authorize accepts widget envelope contracts and resolves command type from event type" do
    context = %{
      correlation_id: "cor-pol-widget-allow",
      request_id: "req-pol-widget-allow",
      auth_context: %{
        subject_id: "usr-viewer",
        roles: ["viewer"],
        authenticated: true
      },
      policy_context: %{policy_version: "v5"}
    }

    command =
      WidgetUiEventEnvelope.new(%{
        type: "unified.button.clicked",
        widget_id: "wid-pol-widget",
        data: %{action: "run"}
      })

    assert {:ok, decision} = Policy.authorize(context, command)
    assert decision.decision == :allow
    assert decision.policy_version == "v5"
    assert decision.request.command.command_type == "unified.button.clicked"
    assert decision.request.command.mutating? == false
    assert decision.request.command.custom_nodes == []
  end
end
