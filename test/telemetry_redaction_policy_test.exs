defmodule JidoCodeUi.TelemetryRedactionPolicyTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry

  setup do
    :ok = Telemetry.reset_events()

    on_exit(fn ->
      :ok = Telemetry.reset_events()
    end)

    :ok
  end

  test "telemetry redacts sensitive keys before recording events and emits redaction diagnostics" do
    :ok =
      Telemetry.emit("ui.policy.denied.v1", %{
        correlation_id: "cor-redaction-apply",
        request_id: "req-redaction-apply",
        error_code: "policy_mutation_denied",
        error_category: "policy",
        error_stage: "policy_authorization",
        redacted_command: %{
          payload: %{
            prompt: "print secrets",
            code: "token=abc123",
            contents: "super secret body"
          }
        },
        details: %{
          api_key: "key-live-abc",
          nested: %{"refresh_token" => "refresh-token-value"}
        }
      })

    events = Telemetry.recent_events(120)

    denied_event =
      Enum.find(events, fn event ->
        event.event_name == "ui.policy.denied.v1" and
          event.correlation_id == "cor-redaction-apply"
      end)

    assert denied_event != nil
    assert denied_event.redaction_applied == true
    assert denied_event.redaction_policy_version == "v1"
    assert get_in(denied_event, [:redacted_command, :payload, :prompt]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :code]) == "[REDACTED]"
    assert get_in(denied_event, [:redacted_command, :payload, :contents]) == "[REDACTED]"
    assert get_in(denied_event, [:details, :api_key]) == "[REDACTED]"
    assert get_in(denied_event, [:details, :nested, "refresh_token"]) == "[REDACTED]"

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.redaction.applied.v1" and
               event.source_event == "ui.policy.denied.v1" and
               event.redaction_policy_version == "v1" and
               event.redacted_field_count >= 3
           end)
  end

  test "telemetry emits redaction miss alerts when suspicious token material survives" do
    :ok =
      Telemetry.emit("ui.ingress.denied.v1", %{
        correlation_id: "cor-redaction-miss",
        request_id: "req-redaction-miss",
        error_code: "ingress_auth_invalid",
        error_category: "ingress",
        error_stage: "ingress_auth",
        note: "Authorization header looked like Bearer abcdefghijklmnop.qrstuvwx.yz012345"
      })

    events = Telemetry.recent_events(120)

    miss_event =
      Enum.find(events, fn event ->
        event.event_name == "ui.redaction.miss.v1" and
          event.source_event == "ui.ingress.denied.v1" and
          event.correlation_id == "cor-redaction-miss"
      end)

    assert miss_event != nil
    assert miss_event.redaction_policy_version == "v1"
    assert miss_event.error_code == "redaction_policy_miss"
    assert miss_event.missed_count >= 1
    assert "note" in miss_event.missed_paths
  end
end
