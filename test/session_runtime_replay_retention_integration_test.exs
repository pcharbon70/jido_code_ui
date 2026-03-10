defmodule JidoCodeUi.SessionRuntimeReplayRetentionIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Runtime.Substrate
  alias JidoCodeUi.Services.UiOrchestrator
  alias JidoCodeUi.Session.RuntimeAgent
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

  test "session transition and retention flows preserve runtime authority with in-memory snapshots" do
    session_id = "sess-int-ret-" <> Integer.to_string(System.unique_integer([:positive]))

    success_command =
      admit_command(
        session_id,
        "cor-int-ret-success",
        "req-int-ret-success",
        %{path: "lib/retention_integration.ex", contents: "baseline"}
      )

    assert {:ok, success_result} = UiOrchestrator.execute(success_command, %{})
    assert success_result.session.metadata.in_memory_only == true
    assert success_result.session.metadata.persistence_adapter == nil

    assert {:ok, baseline_snapshot} = RuntimeAgent.current_snapshot(session_id)
    assert baseline_snapshot.render.rendered == true
    assert baseline_snapshot.active_iur_hash == success_result.compile.iur_hash

    compile_fail_command =
      admit_command(
        session_id,
        "cor-int-ret-compile-fail",
        "req-int-ret-compile-fail",
        %{
          path: "lib/retention_integration.ex",
          contents: "compile-break",
          force_compile_error: true
        }
      )

    assert {:error, %TypedError{error_code: "orchestrator_compile_failed"}} =
             UiOrchestrator.execute(compile_fail_command, %{})

    assert {:ok, after_compile_failure} = RuntimeAgent.current_snapshot(session_id)
    assert after_compile_failure.active_iur_hash == baseline_snapshot.active_iur_hash
    assert after_compile_failure.rollback.status == "retained_last_known_good"
    assert after_compile_failure.rollback.failed_stage == "compile"
    assert after_compile_failure.metadata.in_memory_only == true
    assert after_compile_failure.metadata.persistence_adapter == nil

    render_fail_command =
      admit_command(
        session_id,
        "cor-int-ret-render-fail",
        "req-int-ret-render-fail",
        %{
          path: "lib/retention_integration.ex",
          contents: "render-break",
          force_render_error: true
        }
      )

    assert {:error, %TypedError{error_code: "orchestrator_render_failed"}} =
             UiOrchestrator.execute(render_fail_command, %{})

    assert {:ok, after_render_failure} = RuntimeAgent.current_snapshot(session_id)
    assert after_render_failure.active_iur_hash == baseline_snapshot.active_iur_hash
    assert after_render_failure.rollback.status == "retained_last_known_good"
    assert after_render_failure.rollback.failed_stage == "render"
    assert after_render_failure.metadata.in_memory_only == true
    assert after_render_failure.metadata.persistence_adapter == nil
  end

  test "replay integration validates deterministic parity and emits mismatch diagnostics" do
    session_id = "sess-int-replay-" <> Integer.to_string(System.unique_integer([:positive]))

    success_command =
      admit_command(
        session_id,
        "cor-int-replay-success",
        "req-int-replay-success",
        %{path: "lib/replay_integration.ex", contents: "baseline"}
      )

    assert {:ok, _success_result} = UiOrchestrator.execute(success_command, %{})
    assert {:ok, baseline_snapshot} = RuntimeAgent.current_snapshot(session_id)

    match_stream = [
      %{sequence: 2, accepted: true, iur_hash: baseline_snapshot.active_iur_hash},
      %{sequence: 1, accepted: true, iur_hash: "hash-intermediate"},
      %{sequence: 3, accepted: false, iur_hash: "hash-ignored"}
    ]

    assert {:ok, replay_match} = RuntimeAgent.replay_session(session_id, match_stream)
    assert replay_match.replay.status == "completed"
    assert replay_match.replay.parity_status == "match"
    assert replay_match.replay.expected_iur_hash == baseline_snapshot.active_iur_hash
    assert replay_match.replay.actual_iur_hash == baseline_snapshot.active_iur_hash

    mismatch_stream = [
      %{sequence: 1, accepted: true, iur_hash: "hash-mismatch"}
    ]

    assert {:error,
            %TypedError{
              stage: "session_runtime_replay_parity",
              error_code: "session_replay_parity_mismatch"
            }} = RuntimeAgent.replay_session(session_id, mismatch_stream)

    events = Telemetry.recent_events(400)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.session.replay.parity.v1" and
               event.session_id == session_id and
               event.parity_status == "match"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.session.replay.parity.v1" and
               event.session_id == session_id and
               event.parity_status == "mismatch"
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.session.replay.metric.v1" and
               event.metric == "replay_parity_mismatch_total" and
               event.session_id == session_id
           end)

    assert Enum.any?(events, fn event ->
             event.event_name == "ui.session.failure.v1" and
               event.operation == "replay_session" and
               event.error_code == "session_replay_parity_mismatch" and
               event.session_id == session_id
           end)
  end

  defp admit_command(session_id, correlation_id, request_id, payload) do
    {:ok, admitted} =
      Substrate.admit(%{
        command_type: "save_file",
        session_id: session_id,
        correlation_id: correlation_id,
        request_id: request_id,
        payload: payload,
        auth_context: %{
          subject_id: "usr-session-integration",
          roles: ["editor"],
          authenticated: true,
          policy_context: %{policy_version: "v6"}
        }
      })

    admitted
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
