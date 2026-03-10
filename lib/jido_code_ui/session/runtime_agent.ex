defmodule JidoCodeUi.Session.RuntimeAgent do
  @moduledoc """
  Runtime-authoritative in-memory `UiSessionSnapshot` owner.
  """

  use GenServer

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :session_runtime_agent
  @snapshot_schema_version "v1"
  @snapshot_kind "UiSessionSnapshot"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec create_session(map()) :: {:ok, map()} | {:error, TypedError.t()}
  def create_session(attrs \\ %{})

  def create_session(attrs) when is_map(attrs) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_create", %{operation: "create_session"}) do
      call_runtime({:create_session, attrs}, "create_session")
    end
  end

  def create_session(invalid_attrs) do
    continuity = continuity_ids(invalid_attrs, nil)

    {:error,
     session_error(
       "session_invalid_payload",
       "Session create payload must be a map",
       continuity,
       "session_runtime_create",
       %{schema_path: "$", expected: "map", received: inspect(invalid_attrs)}
     )}
  end

  @spec update_session(String.t(), map()) :: {:ok, map()} | {:error, TypedError.t()}
  def update_session(session_id, attrs) when is_binary(session_id) and is_map(attrs) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_update", %{operation: "update_session"}) do
      call_runtime({:update_session, session_id, attrs}, "update_session")
    end
  end

  def update_session(session_id, attrs) do
    continuity = continuity_ids(attrs, nil)

    {:error,
     session_error(
       "session_invalid_payload",
       "Session update requires a binary session_id and map attrs",
       continuity,
       "session_runtime_update",
       %{schema_path: "$", session_id: inspect(session_id), attrs: inspect(attrs)}
     )}
  end

  @spec replay_session(String.t(), list()) :: {:ok, map()} | {:error, TypedError.t()}
  def replay_session(session_id, event_stream)
      when is_binary(session_id) and is_list(event_stream) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_replay", %{operation: "replay_session"}) do
      call_runtime({:replay_session, session_id, event_stream}, "replay_session")
    end
  end

  def replay_session(session_id, event_stream) do
    continuity = continuity_ids(event_stream, nil)

    {:error,
     session_error(
       "session_invalid_payload",
       "Session replay requires a binary session_id and list event_stream",
       continuity,
       "session_runtime_replay",
       %{schema_path: "$", session_id: inspect(session_id), event_stream: inspect(event_stream)}
     )}
  end

  @spec current_snapshot(String.t()) :: {:ok, map()} | {:error, TypedError.t()}
  def current_snapshot(session_id) when is_binary(session_id) do
    with :ok <-
           StartupGuard.ensure_ready("session_runtime_snapshot", %{operation: "current_snapshot"}) do
      call_runtime({:current_snapshot, session_id}, "current_snapshot")
    end
  end

  def current_snapshot(session_id) do
    continuity = continuity_ids(%{}, nil)

    {:error,
     session_error(
       "session_invalid_payload",
       "Session snapshot lookup requires a binary session_id",
       continuity,
       "session_runtime_snapshot",
       %{schema_path: "$.session_id", received: inspect(session_id)}
     )}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:create_session, attrs}, _from, state) do
    continuity = continuity_ids(attrs, nil)
    session_id = resolve_session_id(attrs)

    case Map.fetch(state.sessions, session_id) do
      {:ok, existing_snapshot} ->
        {:reply, {:ok, existing_snapshot}, state}

      :error ->
        with {:ok, snapshot} <- build_initial_snapshot(session_id, attrs, continuity) do
          next_state = put_in(state, [:sessions, session_id], snapshot)
          {:reply, {:ok, snapshot}, next_state}
        else
          {:error, %TypedError{} = typed_error} -> {:reply, {:error, typed_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:update_session, session_id, attrs}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, existing_snapshot} ->
        continuity = continuity_ids(attrs, existing_snapshot.continuity)

        with :ok <- ensure_expected_revision(existing_snapshot, attrs, continuity),
             {:ok, updated_snapshot} <-
               build_updated_snapshot(existing_snapshot, attrs, continuity) do
          next_state = put_in(state, [:sessions, session_id], updated_snapshot)
          {:reply, {:ok, updated_snapshot}, next_state}
        else
          {:error, %TypedError{} = typed_error} -> {:reply, {:error, typed_error}, state}
        end

      :error ->
        continuity = continuity_ids(attrs, nil)
        {:reply, {:error, not_found_error(session_id, continuity)}, state}
    end
  end

  @impl true
  def handle_call({:replay_session, session_id, event_stream}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, snapshot} ->
        continuity = continuity_ids(event_stream, snapshot.continuity)

        with {:ok, admitted_events} <- normalize_replay_events(event_stream, continuity),
             {:ok, replayed_snapshot} <- apply_replay(snapshot, admitted_events, continuity) do
          next_state = put_in(state, [:sessions, session_id], replayed_snapshot)
          {:reply, {:ok, replayed_snapshot}, next_state}
        else
          {:error, %TypedError{} = typed_error} -> {:reply, {:error, typed_error}, state}
        end

      :error ->
        continuity = continuity_ids(event_stream, nil)
        {:reply, {:error, not_found_error(session_id, continuity)}, state}
    end
  end

  @impl true
  def handle_call({:current_snapshot, session_id}, _from, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, snapshot} ->
        {:reply, {:ok, snapshot}, state}

      :error ->
        continuity = continuity_ids(%{}, nil)
        {:reply, {:error, not_found_error(session_id, continuity)}, state}
    end
  end

  defp call_runtime(message, operation) do
    case GenServer.call(__MODULE__, message) do
      {:ok, snapshot} = ok ->
        Telemetry.emit("ui.session.transition.v1", %{
          operation: operation,
          session_id: snapshot.session_id,
          active_iur_hash: snapshot.active_iur_hash,
          revision: snapshot.revision,
          correlation_id: snapshot.continuity.correlation_id,
          request_id: snapshot.continuity.request_id
        })

        ok

      {:error, %TypedError{} = typed_error} = error ->
        emit_session_failure(operation, typed_error)
        error
    end
  end

  defp build_initial_snapshot(session_id, attrs, continuity) do
    compile_result = normalize_optional_map(attrs, :compile_result)
    render_result = normalize_optional_map(attrs, :render_result)
    compile_contract = compile_contract(compile_result)
    render_contract = render_contract(render_result)

    snapshot = %{
      schema_version: @snapshot_schema_version,
      snapshot_kind: @snapshot_kind,
      session_id: session_id,
      route_key: resolve_route_key(attrs, nil),
      continuity: continuity,
      compile: compile_contract,
      render: render_contract,
      active_iur_hash: compile_contract.iur_hash,
      replay: %{
        status: "not_started",
        event_count: 0,
        expected_iur_hash: compile_contract.iur_hash,
        actual_iur_hash: nil,
        last_replay_at: nil
      },
      rollback: nil,
      metadata: metadata_contract(attrs),
      revision: 1,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    {:ok, snapshot}
  end

  defp build_updated_snapshot(existing_snapshot, attrs, continuity) do
    retention = normalize_optional_map(attrs, :retention)

    if retention != %{} do
      build_retained_snapshot(existing_snapshot, attrs, retention, continuity)
    else
      do_build_updated_snapshot(existing_snapshot, attrs, continuity)
    end
  end

  defp do_build_updated_snapshot(existing_snapshot, attrs, continuity) do
    compile_result = normalize_optional_map(attrs, :compile_result)
    render_result = normalize_optional_map(attrs, :render_result)

    compile_contract =
      if compile_result == %{} do
        existing_snapshot.compile
      else
        compile_contract(compile_result)
      end

    render_contract =
      if render_result == %{} do
        existing_snapshot.render
      else
        render_contract(render_result)
      end

    next_snapshot = %{
      existing_snapshot
      | route_key: resolve_route_key(attrs, existing_snapshot.route_key),
        continuity: continuity,
        compile: compile_contract,
        render: render_contract,
        active_iur_hash: compile_contract.iur_hash || existing_snapshot.active_iur_hash,
        metadata: Map.merge(existing_snapshot.metadata, metadata_contract(attrs)),
        revision: existing_snapshot.revision + 1,
        updated_at: DateTime.utc_now()
    }

    {:ok, next_snapshot}
  end

  defp build_retained_snapshot(existing_snapshot, attrs, retention, continuity) do
    with {:ok, rollback_marker} <- rollback_marker(existing_snapshot, retention, continuity) do
      next_snapshot = %{
        existing_snapshot
        | route_key: resolve_route_key(attrs, existing_snapshot.route_key),
          continuity: continuity,
          rollback: rollback_marker,
          metadata: Map.merge(existing_snapshot.metadata, metadata_contract(attrs)),
          revision: existing_snapshot.revision + 1,
          updated_at: DateTime.utc_now()
      }

      Telemetry.emit("ui.session.retention.applied.v1", %{
        session_id: next_snapshot.session_id,
        rollback_status: rollback_marker.status,
        failed_stage: rollback_marker.failed_stage,
        failed_error_code: rollback_marker.failed_error_code,
        active_iur_hash: next_snapshot.active_iur_hash,
        revision: next_snapshot.revision,
        correlation_id: continuity.correlation_id,
        request_id: continuity.request_id
      })

      {:ok, next_snapshot}
    end
  end

  defp rollback_marker(snapshot, retention, continuity) do
    failed_stage = normalize_string(get_value(retention, :failed_stage))

    if failed_stage in ["compile", "render", "replay"] do
      has_last_known_good? =
        snapshot.render.rendered == true and is_binary(snapshot.active_iur_hash)

      require_last_known_good? = get_value(retention, :require_last_known_good) == true

      if require_last_known_good? and not has_last_known_good? do
        {:error,
         session_error(
           "session_retention_violation",
           "No last-known-good projection exists for required retention",
           continuity,
           "session_runtime_retention",
           %{
             session_id: snapshot.session_id,
             failed_stage: failed_stage,
             snapshot_revision: snapshot.revision,
             active_iur_hash: snapshot.active_iur_hash,
             replay_status: get_in(snapshot, [:replay, :status]),
             replay_event_count: get_in(snapshot, [:replay, :event_count]),
             rollback_status: "violation_no_known_good"
           }
         )}
      else
        status =
          if has_last_known_good? do
            "retained_last_known_good"
          else
            "retention_skipped_no_known_good"
          end

        {:ok,
         %{
           status: status,
           failed_stage: failed_stage,
           failed_error_code: normalize_string(get_value(retention, :error_code)),
           failed_error_category: normalize_string(get_value(retention, :error_category)),
           failed_error_stage: normalize_string(get_value(retention, :error_stage)),
           retained_revision: snapshot.revision,
           retained_iur_hash: snapshot.active_iur_hash,
           retained_rendered: snapshot.render.rendered == true,
           replay_status: get_in(snapshot, [:replay, :status]),
           replay_event_count: get_in(snapshot, [:replay, :event_count]),
           diagnostics: normalize_optional_map(retention, :details),
           applied_at: DateTime.utc_now()
         }}
      end
    else
      {:error,
       session_error(
         "session_retention_invalid_payload",
         "Retention failed_stage must be compile, render, or replay",
         continuity,
         "session_runtime_retention",
         %{
           session_id: snapshot.session_id,
           schema_path: "$.retention.failed_stage",
           expected: "compile|render|replay",
           received: inspect(get_value(retention, :failed_stage)),
           rollback_status: "invalid_payload"
         }
       )}
    end
  end

  defp normalize_replay_events(event_stream, continuity) do
    if Enum.all?(event_stream, &is_map/1) do
      admitted_events =
        event_stream
        |> Enum.filter(&admit_replay_event?/1)
        |> Enum.sort_by(fn event ->
          {sequence(event), normalize_string(get_value(event, :type)) || "event"}
        end)

      {:ok, admitted_events}
    else
      {:error,
       session_error(
         "session_replay_invalid_stream",
         "Replay event stream must contain only map envelopes",
         continuity,
         "session_runtime_replay",
         %{schema_path: "$.event_stream", expected: "list(map)", received: inspect(event_stream)}
       )}
    end
  end

  defp apply_replay(snapshot, admitted_events, continuity) do
    actual_iur_hash =
      admitted_events
      |> List.last()
      |> case do
        nil -> snapshot.active_iur_hash
        event -> normalize_string(get_value(event, :iur_hash)) || snapshot.active_iur_hash
      end

    replay_contract = %{
      status: "completed",
      event_count: length(admitted_events),
      expected_iur_hash: snapshot.active_iur_hash,
      actual_iur_hash: actual_iur_hash,
      last_replay_at: DateTime.utc_now()
    }

    replayed_snapshot = %{
      snapshot
      | replay: replay_contract,
        continuity: continuity,
        revision: snapshot.revision + 1,
        updated_at: DateTime.utc_now()
    }

    Telemetry.emit("ui.session.replay.completed.v1", %{
      session_id: replayed_snapshot.session_id,
      event_count: replay_contract.event_count,
      expected_iur_hash: replay_contract.expected_iur_hash,
      actual_iur_hash: replay_contract.actual_iur_hash,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    })

    {:ok, replayed_snapshot}
  end

  defp resolve_session_id(attrs) do
    normalize_string(get_value(attrs, :session_id)) || deterministic_session_id(attrs)
  end

  defp deterministic_session_id(attrs) do
    source =
      normalize_string(get_value(attrs, :route_key)) ||
        normalize_string(get_in(attrs, [:compile_result, :iur_hash])) || "default"

    "sess-" <> Integer.to_string(:erlang.phash2(source, 1_000_000))
  end

  defp resolve_route_key(attrs, existing_route_key) do
    normalize_string(get_value(attrs, :route_key)) || existing_route_key || "route-unset"
  end

  defp metadata_contract(attrs) do
    %{
      policy_version: normalize_string(get_value(attrs, :policy_version)) || "v1",
      in_memory_only: true,
      persistence_adapter: nil
    }
  end

  defp compile_contract(compile_result) when is_map(compile_result) do
    %{
      compile_authority:
        normalize_string(get_value(compile_result, :compile_authority)) || "server",
      dsl_version: normalize_string(get_value(compile_result, :dsl_version)) || "v1",
      iur_version: normalize_string(get_value(compile_result, :iur_version)) || "v1",
      iur_hash: normalize_string(get_value(compile_result, :iur_hash)),
      diagnostics: normalize_list(get_value(compile_result, :diagnostics))
    }
  end

  defp compile_contract(_compile_result) do
    %{
      compile_authority: "server",
      dsl_version: "v1",
      iur_version: "v1",
      iur_hash: nil,
      diagnostics: []
    }
  end

  defp render_contract(render_result) when is_map(render_result) do
    continuity = normalize_optional_map(render_result, :continuity)

    %{
      rendered: get_value(render_result, :rendered) == true,
      payload_class:
        normalize_string(get_in(render_result, [:render_metadata, :payload_class])) || "unknown",
      route_key:
        normalize_string(get_in(render_result, [:projection, :route_key])) ||
          normalize_string(get_value(continuity, :route_key)),
      render_token: normalize_string(get_value(continuity, :render_token))
    }
  end

  defp render_contract(_render_result) do
    %{
      rendered: false,
      payload_class: "unknown",
      route_key: nil,
      render_token: nil
    }
  end

  defp ensure_expected_revision(snapshot, attrs, continuity) do
    case get_value(attrs, :expected_revision) do
      nil ->
        :ok

      revision when is_integer(revision) and revision == snapshot.revision ->
        :ok

      invalid ->
        {:error,
         session_error(
           "session_snapshot_stale",
           "Session snapshot revision does not match expected revision",
           continuity,
           "session_runtime_transition",
           %{
             session_id: snapshot.session_id,
             expected_revision: invalid,
             actual_revision: snapshot.revision,
             active_iur_hash: snapshot.active_iur_hash,
             replay_status: get_in(snapshot, [:replay, :status]),
             replay_event_count: get_in(snapshot, [:replay, :event_count])
           }
         )}
    end
  end

  defp not_found_error(session_id, continuity) do
    session_error(
      "session_not_found",
      "Session snapshot was not found",
      continuity,
      "session_runtime_lookup",
      %{session_id: session_id}
    )
  end

  defp session_error(error_code, message, continuity, stage, details) do
    TypedError.new(
      error_code: error_code,
      category: "session",
      stage: stage,
      retryable: false,
      message: message,
      details: details,
      correlation_id: continuity.correlation_id,
      request_id: continuity.request_id
    )
  end

  defp emit_session_failure(operation, %TypedError{} = typed_error) do
    diagnostics = session_failure_diagnostics(typed_error.details)

    Telemetry.emit(
      "ui.session.failure.v1",
      Map.merge(
        %{
          operation: operation,
          error_code: typed_error.error_code,
          error_category: typed_error.category,
          error_stage: typed_error.stage,
          details: typed_error.details,
          correlation_id: typed_error.correlation_id,
          request_id: typed_error.request_id
        },
        diagnostics
      )
    )
  end

  defp session_failure_diagnostics(details) when is_map(details) do
    %{
      session_id: normalize_string(get_value(details, :session_id)),
      snapshot_revision: normalize_integer(get_value(details, :snapshot_revision)),
      replay_status: normalize_string(get_value(details, :replay_status)),
      replay_event_count: normalize_integer(get_value(details, :replay_event_count)),
      active_iur_hash: normalize_string(get_value(details, :active_iur_hash)),
      rollback_status: normalize_string(get_value(details, :rollback_status))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp session_failure_diagnostics(_details), do: %{}

  defp admit_replay_event?(event) when is_map(event) do
    accepted_flag = get_value(event, :accepted)
    policy_decision = normalize_string(get_value(event, :policy_decision))

    cond do
      accepted_flag == false -> false
      policy_decision in ["deny", "rejected"] -> false
      true -> true
    end
  end

  defp sequence(event) do
    case get_value(event, :sequence) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp continuity_ids(source, fallback) when is_list(source) do
    source
    |> List.first()
    |> continuity_ids(fallback)
  end

  defp continuity_ids(source, fallback) do
    fallback_correlation_id = if is_map(fallback), do: fallback.correlation_id, else: nil
    fallback_request_id = if is_map(fallback), do: fallback.request_id, else: nil

    %{
      correlation_id:
        normalize_string(get_value(source, :correlation_id)) ||
          normalize_string(fallback_correlation_id) || default_id("cor"),
      request_id:
        normalize_string(get_value(source, :request_id)) ||
          normalize_string(fallback_request_id) || default_id("req")
    }
  end

  defp normalize_optional_map(map, key) when is_map(map) do
    case get_value(map, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp normalize_optional_map(_map, _key), do: %{}

  defp normalize_list(values) when is_list(values), do: values
  defp normalize_list(_values), do: []

  defp normalize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_string()
  end

  defp normalize_string(_value), do: nil

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(_value), do: nil

  defp get_value(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      Map.get(map, Atom.to_string(key))
    end
  end

  defp get_value(_map, _key), do: nil

  defp default_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
