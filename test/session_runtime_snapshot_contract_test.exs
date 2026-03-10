defmodule JidoCodeUi.SessionRuntimeSnapshotContractTest do
  use ExUnit.Case, async: false

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.Session.RuntimeAgent
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

  test "create_session defines canonical in-memory UiSessionSnapshot contract" do
    assert {:ok, snapshot} =
             RuntimeAgent.create_session(%{
               session_id: "sess-runtime-contract",
               route_key: "route-runtime-contract",
               policy_version: "v3",
               compile_result: %{
                 compile_authority: "server",
                 dsl_version: "v1",
                 iur_version: "v1",
                 iur_hash: "hash-runtime-contract",
                 diagnostics: []
               },
               correlation_id: "cor-runtime-contract",
               request_id: "req-runtime-contract"
             })

    assert snapshot.snapshot_kind == "UiSessionSnapshot"
    assert snapshot.schema_version == "v1"
    assert snapshot.session_id == "sess-runtime-contract"
    assert snapshot.route_key == "route-runtime-contract"
    assert snapshot.compile.compile_authority == "server"
    assert snapshot.compile.iur_hash == "hash-runtime-contract"
    assert snapshot.active_iur_hash == "hash-runtime-contract"
    assert snapshot.render.rendered == false
    assert snapshot.metadata.in_memory_only == true
    assert snapshot.metadata.persistence_adapter == nil
    assert snapshot.continuity.correlation_id == "cor-runtime-contract"
    assert snapshot.continuity.request_id == "req-runtime-contract"

    assert {:ok, current} = RuntimeAgent.current_snapshot("sess-runtime-contract")
    assert current.revision == snapshot.revision
    assert current.active_iur_hash == "hash-runtime-contract"

    assert Enum.any?(Telemetry.recent_events(60), fn event ->
             event.event_name == "ui.session.transition.v1" and
               event.operation == "create_session" and
               event.session_id == "sess-runtime-contract"
           end)
  end

  test "update_session applies accepted render outcomes and rejects stale revisions" do
    assert {:ok, created} =
             RuntimeAgent.create_session(%{
               session_id: "sess-runtime-update",
               route_key: "route-runtime-update",
               compile_result: %{iur_hash: "hash-update-initial"},
               correlation_id: "cor-runtime-update-create",
               request_id: "req-runtime-update-create"
             })

    assert {:ok, updated} =
             RuntimeAgent.update_session("sess-runtime-update", %{
               expected_revision: created.revision,
               render_result: %{
                 rendered: true,
                 render_metadata: %{payload_class: "small"},
                 continuity: %{
                   render_token: "rnd-runtime-update",
                   route_key: "route-runtime-update"
                 }
               },
               correlation_id: "cor-runtime-update-ok",
               request_id: "req-runtime-update-ok"
             })

    assert updated.revision == created.revision + 1
    assert updated.render.rendered == true
    assert updated.render.payload_class == "small"
    assert updated.render.render_token == "rnd-runtime-update"
    assert updated.continuity.correlation_id == "cor-runtime-update-ok"
    assert updated.continuity.request_id == "req-runtime-update-ok"

    assert {:error,
            %TypedError{
              category: "session",
              stage: "session_runtime_transition",
              error_code: "session_snapshot_stale"
            }} =
             RuntimeAgent.update_session("sess-runtime-update", %{
               expected_revision: created.revision,
               correlation_id: "cor-runtime-update-stale",
               request_id: "req-runtime-update-stale"
             })

    assert Enum.any?(Telemetry.recent_events(80), fn event ->
             event.event_name == "ui.session.failure.v1" and
               event.operation == "update_session" and
               event.error_code == "session_snapshot_stale"
           end)
  end

  test "current_snapshot and payload validation return typed missing or invalid errors" do
    assert {:error,
            %TypedError{
              category: "session",
              stage: "session_runtime_lookup",
              error_code: "session_not_found"
            }} = RuntimeAgent.current_snapshot("sess-runtime-missing")

    assert {:error,
            %TypedError{
              category: "session",
              stage: "session_runtime_snapshot",
              error_code: "session_invalid_payload"
            }} = RuntimeAgent.current_snapshot(42)
  end

  test "replay_session applies deterministic replay ordering metadata to snapshots" do
    assert {:ok, created} =
             RuntimeAgent.create_session(%{
               session_id: "sess-runtime-replay",
               route_key: "route-runtime-replay",
               compile_result: %{iur_hash: "hash-replay-base"},
               correlation_id: "cor-runtime-replay-create",
               request_id: "req-runtime-replay-create"
             })

    event_stream = [
      %{sequence: 2, accepted: true, iur_hash: "hash-replay-final"},
      %{sequence: 1, accepted: true, iur_hash: "hash-replay-mid"},
      %{sequence: 3, accepted: false, iur_hash: "hash-replay-ignored"}
    ]

    assert {:ok, replayed} = RuntimeAgent.replay_session("sess-runtime-replay", event_stream)

    assert replayed.revision == created.revision + 1
    assert replayed.replay.status == "completed"
    assert replayed.replay.event_count == 2
    assert replayed.replay.expected_iur_hash == "hash-replay-base"
    assert replayed.replay.actual_iur_hash == "hash-replay-final"
    assert replayed.continuity.correlation_id == "cor-runtime-replay-create"
    assert replayed.continuity.request_id == "req-runtime-replay-create"

    assert Enum.any?(Telemetry.recent_events(80), fn event ->
             event.event_name == "ui.session.replay.completed.v1" and
               event.session_id == "sess-runtime-replay" and
               event.event_count == 2
           end)
  end

  test "update_session retains last-known-good projection and records rollback markers" do
    assert {:ok, created} =
             RuntimeAgent.create_session(%{
               session_id: "sess-runtime-retain",
               route_key: "route-runtime-retain",
               compile_result: %{iur_hash: "hash-retain-good"},
               correlation_id: "cor-runtime-retain-create",
               request_id: "req-runtime-retain-create"
             })

    assert {:ok, rendered} =
             RuntimeAgent.update_session("sess-runtime-retain", %{
               expected_revision: created.revision,
               render_result: %{
                 rendered: true,
                 render_metadata: %{payload_class: "small"}
               },
               correlation_id: "cor-runtime-retain-render",
               request_id: "req-runtime-retain-render"
             })

    assert {:ok, retained} =
             RuntimeAgent.update_session("sess-runtime-retain", %{
               expected_revision: rendered.revision,
               retention: %{
                 failed_stage: "compile",
                 error_code: "dsl_compile_failed",
                 error_category: "compile",
                 error_stage: "dsl_compile",
                 details: %{reason: "simulated compile failure"}
               },
               correlation_id: "cor-runtime-retain-failure",
               request_id: "req-runtime-retain-failure"
             })

    assert retained.revision == rendered.revision + 1
    assert retained.active_iur_hash == "hash-retain-good"
    assert retained.compile == rendered.compile
    assert retained.render == rendered.render
    assert retained.rollback.status == "retained_last_known_good"
    assert retained.rollback.failed_stage == "compile"
    assert retained.rollback.failed_error_code == "dsl_compile_failed"
    assert retained.rollback.retained_iur_hash == "hash-retain-good"
    assert retained.rollback.retained_rendered == true

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.session.retention.applied.v1" and
               event.session_id == "sess-runtime-retain" and
               event.rollback_status == "retained_last_known_good"
           end)
  end

  test "retention violations emit typed outcomes with replay and snapshot diagnostics" do
    assert {:ok, created} =
             RuntimeAgent.create_session(%{
               session_id: "sess-runtime-retain-violation",
               route_key: "route-runtime-retain-violation",
               compile_result: %{iur_hash: "hash-retain-violation"},
               correlation_id: "cor-runtime-retain-violation-create",
               request_id: "req-runtime-retain-violation-create"
             })

    assert {:error,
            %TypedError{
              category: "session",
              stage: "session_runtime_retention",
              error_code: "session_retention_violation"
            }} =
             RuntimeAgent.update_session("sess-runtime-retain-violation", %{
               expected_revision: created.revision,
               retention: %{
                 failed_stage: "render",
                 error_code: "iur_adapter_failed",
                 error_category: "render",
                 error_stage: "iur_render_adapter",
                 require_last_known_good: true
               },
               correlation_id: "cor-runtime-retain-violation-failure",
               request_id: "req-runtime-retain-violation-failure"
             })

    assert Enum.any?(Telemetry.recent_events(100), fn event ->
             event.event_name == "ui.session.failure.v1" and
               event.operation == "update_session" and
               event.error_code == "session_retention_violation" and
               event.rollback_status == "violation_no_known_good" and
               event.replay_status == "not_started" and
               event.session_id == "sess-runtime-retain-violation"
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
