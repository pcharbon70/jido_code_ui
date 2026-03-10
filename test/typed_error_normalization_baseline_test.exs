defmodule JidoCodeUi.TypedErrorNormalizationBaselineTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.TypedError

  setup do
    :ok = Telemetry.reset_events()

    on_exit(fn ->
      :ok = Telemetry.reset_events()
    end)

    :ok
  end

  test "typed error conformance table validates canonical category and stage mappings" do
    assert %{status: :pass, expected_category: "compile", expected_stage_prefix: "dsl_"} =
             TypedError.conformance("dsl_schema_invalid", "compile", "dsl_validation")

    assert %{status: :pass, expected_category: "boundary", expected_stage_prefix: "session_"} =
             TypedError.conformance(
               "session_authority_violation",
               "boundary",
               "session_mutation_authority"
             )

    assert %{status: :fail, expected_category: "boundary", expected_stage_prefix: "session_"} =
             TypedError.conformance(
               "session_authority_violation",
               "session",
               "session_mutation_authority"
             )

    assert %{status: :fail, expected_category: "policy", expected_stage_prefix: "policy_"} =
             TypedError.conformance(
               "policy_mutation_denied",
               "ingress",
               "ingress_validation"
             )
  end

  test "telemetry emits typed error conformance diagnostics and counters" do
    :ok =
      Telemetry.emit("ui.dsl.compile.failed.v1", %{
        error_code: "dsl_schema_invalid",
        error_category: "compile",
        error_stage: "dsl_validation",
        correlation_id: "cor-typed-pass",
        request_id: "req-typed-pass"
      })

    :ok =
      Telemetry.emit("ui.policy.denied.v1", %{
        error_code: "policy_mutation_denied",
        error_category: "ingress",
        error_stage: "ingress_validation",
        correlation_id: "cor-typed-fail",
        request_id: "req-typed-fail"
      })

    events = Telemetry.recent_events(80)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.conformance.v1" and
               event.error_code == "dsl_schema_invalid" and
               event.status == "pass"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.conformance.v1" and
               event.error_code == "policy_mutation_denied" and
               event.status == "fail"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.metric.v1" and
               event.metric == "typed_error_total" and
               event.error_code == "dsl_schema_invalid"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.metric.v1" and
               event.metric == "typed_error_conformance_failures_total" and
               event.error_code == "policy_mutation_denied"
           end)
  end

  test "boundary session authority errors emit pass diagnostics without failure counters" do
    :ok =
      Telemetry.emit("runtime.startup.boundary_denied", %{
        error_code: "session_authority_violation",
        category: "boundary",
        stage: "session_mutation_authority",
        correlation_id: "cor-boundary-pass",
        request_id: "req-boundary-pass"
      })

    events = Telemetry.recent_events(60)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.conformance.v1" and
               event.error_code == "session_authority_violation" and
               event.status == "pass"
           end)

    refute Enum.any?(events, fn event ->
             event.event_name == "ui.typed_error.metric.v1" and
               event.metric == "typed_error_conformance_failures_total" and
               event.error_code == "session_authority_violation"
           end)
  end
end
