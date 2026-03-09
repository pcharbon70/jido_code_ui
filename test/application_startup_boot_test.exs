defmodule JidoCodeUi.ApplicationStartupBootTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Runtime.ControlPlaneBoundary
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.TypedError

  setup do
    defaults = JidoCodeUi.Application.runtime_ready_children()
    :ok = StartupLifecycle.set_expected_children(defaults)

    on_exit(fn ->
      :ok = StartupLifecycle.set_expected_children(defaults)
    end)

    :ok
  end

  test "runtime child startup order is deterministic" do
    assert JidoCodeUi.Application.runtime_child_order() == [
             JidoCodeUi.Runtime.StartupLifecycle,
             JidoCodeUi.Runtime.Substrate,
             JidoCodeUi.Security.Policy,
             JidoCodeUi.Services.UiOrchestrator,
             JidoCodeUi.Services.DslCompiler,
             JidoCodeUi.Services.IurRenderer,
             JidoCodeUi.Session.RuntimeAgent
           ]
  end

  test "root supervisor restart semantics are explicitly configured" do
    assert JidoCodeUi.Application.supervisor_opts()[:strategy] == :one_for_one
    assert JidoCodeUi.Application.supervisor_opts()[:max_restarts] == 5
    assert JidoCodeUi.Application.supervisor_opts()[:max_seconds] == 30
  end

  test "runtime wiring passes control-plane boundary validation" do
    assert :ok = JidoCodeUi.Application.validate_runtime_wiring()
  end

  test "runtime wiring fails when required child order is violated" do
    bad_order = [
      JidoCodeUi.Runtime.StartupLifecycle,
      JidoCodeUi.Services.UiOrchestrator,
      JidoCodeUi.Runtime.Substrate,
      JidoCodeUi.Security.Policy,
      JidoCodeUi.Services.DslCompiler,
      JidoCodeUi.Services.IurRenderer,
      JidoCodeUi.Session.RuntimeAgent
    ]

    assert {:error,
            %TypedError{
              category: "boundary",
              error_code: "startup_child_order_violation"
            }} = JidoCodeUi.Application.validate_runtime_wiring(bad_order)
  end

  test "runtime wiring fails when required session runtime child is missing" do
    missing_session = [
      JidoCodeUi.Runtime.StartupLifecycle,
      JidoCodeUi.Runtime.Substrate,
      JidoCodeUi.Security.Policy,
      JidoCodeUi.Services.UiOrchestrator,
      JidoCodeUi.Services.DslCompiler,
      JidoCodeUi.Services.IurRenderer
    ]

    assert {:error,
            %TypedError{
              category: "boundary",
              error_code: "missing_required_child"
            }} = JidoCodeUi.Application.validate_runtime_wiring(missing_session)
  end

  test "session mutation authority allows only session runtime agent" do
    assert :ok = ControlPlaneBoundary.authorize_session_mutation(JidoCodeUi.Session.RuntimeAgent)

    assert {:error,
            %TypedError{
              category: "boundary",
              error_code: "session_authority_violation",
              stage: "session_mutation_authority"
            }} = ControlPlaneBoundary.authorize_session_mutation(JidoCodeUi.Runtime.Substrate)
  end

  test "ingress admission is blocked before readiness" do
    :ok = StartupLifecycle.set_expected_children([:runtime_substrate, :missing_dependency])

    assert {:error,
            %TypedError{
              category: "readiness",
              stage: "ingress_admission",
              error_code: "startup_not_ready"
            }} = Substrate.admit(%{payload: "blocked"})
  end

  test "ingress admission succeeds once runtime is ready" do
    assert_eventually(fn -> StartupLifecycle.ready?() end)

    assert {:ok, admitted} =
             Substrate.admit(%{
               correlation_id: "cor-fixed",
               request_id: "req-fixed",
               payload: "accepted"
             })

    assert admitted.correlation_id == "cor-fixed"
    assert admitted.request_id == "req-fixed"
    assert admitted.payload == "accepted"
    assert Map.has_key?(admitted, :admitted_at)
  end

  test "startup lifecycle events contain continuity metadata" do
    assert_eventually(fn -> StartupLifecycle.ready?() end)

    events = StartupLifecycle.recent_events(100)

    assert Enum.any?(events, &(&1.event == :startup_ready))

    assert Enum.all?(events, fn event ->
             is_binary(event.correlation_id) and
               String.starts_with?(event.correlation_id, "cor-") and
               is_binary(event.request_id) and
               String.starts_with?(event.request_id, "req-")
           end)
  end

  test "restart telemetry is emitted when a child restarts" do
    policy_pid = Process.whereis(JidoCodeUi.Security.Policy)
    assert is_pid(policy_pid)

    Process.exit(policy_pid, :kill)

    assert_eventually(fn ->
      restarted = Process.whereis(JidoCodeUi.Security.Policy)
      events = StartupLifecycle.recent_events(200)

      is_pid(restarted) and restarted != policy_pid and
        Enum.any?(
          events,
          &(&1.event == :startup_child_restarted and &1.child == :security_policy)
        )
    end)
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
