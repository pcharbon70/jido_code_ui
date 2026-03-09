defmodule JidoCodeUi.TypedError do
  @moduledoc """
  Canonical typed error shape for runtime and startup failures.
  """

  @enforce_keys [:error_code, :category, :stage, :retryable, :message]
  defstruct [
    :error_code,
    :category,
    :stage,
    :retryable,
    :message,
    :details,
    :correlation_id,
    :request_id
  ]

  @type t :: %__MODULE__{
          error_code: String.t(),
          category: String.t(),
          stage: String.t(),
          retryable: boolean(),
          message: String.t(),
          details: map(),
          correlation_id: String.t(),
          request_id: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      error_code: Keyword.fetch!(opts, :error_code),
      category: Keyword.fetch!(opts, :category),
      stage: Keyword.fetch!(opts, :stage),
      retryable: Keyword.fetch!(opts, :retryable),
      message: Keyword.fetch!(opts, :message),
      details: Keyword.get(opts, :details, %{}),
      correlation_id: Keyword.fetch!(opts, :correlation_id),
      request_id: Keyword.fetch!(opts, :request_id)
    }
  end

  @spec startup(atom() | String.t(), term(), keyword()) :: t()
  def startup(code, reason, opts \\ []) do
    ids = continuity_ids(opts)
    details = Map.merge(%{reason: inspect(reason)}, Keyword.get(opts, :details, %{}))

    new(
      error_code: to_string(code),
      category: "startup",
      stage: Keyword.get(opts, :stage, "root_boot"),
      retryable: Keyword.get(opts, :retryable, false),
      message: Keyword.get(opts, :message, "Startup failure"),
      details: details,
      correlation_id: ids.correlation_id,
      request_id: ids.request_id
    )
  end

  @spec readiness(String.t(), keyword()) :: t()
  def readiness(message, opts \\ []) do
    ids = continuity_ids(opts)

    new(
      error_code: Keyword.get(opts, :error_code, "startup_not_ready"),
      category: "readiness",
      stage: Keyword.get(opts, :stage, "ingress_admission"),
      retryable: Keyword.get(opts, :retryable, true),
      message: message,
      details: Keyword.get(opts, :details, %{}),
      correlation_id: ids.correlation_id,
      request_id: ids.request_id
    )
  end

  @spec boundary(atom() | String.t(), String.t(), keyword()) :: t()
  def boundary(code, message, opts \\ []) do
    ids = continuity_ids(opts)

    new(
      error_code: to_string(code),
      category: "boundary",
      stage: Keyword.get(opts, :stage, "startup_boundary"),
      retryable: Keyword.get(opts, :retryable, false),
      message: message,
      details: Keyword.get(opts, :details, %{}),
      correlation_id: ids.correlation_id,
      request_id: ids.request_id
    )
  end

  @spec ingress(atom() | String.t(), String.t(), keyword()) :: t()
  def ingress(code, message, opts \\ []) do
    ids = continuity_ids(opts)

    new(
      error_code: to_string(code),
      category: Keyword.get(opts, :category, "ingress"),
      stage: Keyword.get(opts, :stage, "ingress_admission"),
      retryable: Keyword.get(opts, :retryable, false),
      message: message,
      details: Keyword.get(opts, :details, %{}),
      correlation_id: ids.correlation_id,
      request_id: ids.request_id
    )
  end

  @spec classify_startup_failure(term(), keyword()) :: t()
  def classify_startup_failure(reason, opts \\ []) do
    stage = Keyword.get(opts, :stage, "application_start")

    case reason do
      {:shutdown, {:failed_to_start_child, child, child_reason}} ->
        startup(:dependency_start_failed, child_reason,
          stage: stage,
          retryable: true,
          message: "A required runtime child failed to start",
          details: %{child: inspect(child)}
        )

      {:shutdown, {:timeout, timeout_reason}} ->
        startup(:startup_timeout, timeout_reason,
          stage: stage,
          retryable: true,
          message: "Runtime startup timed out"
        )

      :timeout ->
        startup(:startup_timeout, reason,
          stage: stage,
          retryable: true,
          message: "Runtime startup timed out"
        )

      other ->
        startup(:root_supervisor_start_failed, other,
          stage: stage,
          retryable: false,
          message: "Failed to start jido_code_ui root supervisor"
        )
    end
  end

  defp continuity_ids(opts) do
    %{
      correlation_id:
        Keyword.get(
          opts,
          :correlation_id,
          "cor-" <> Integer.to_string(System.unique_integer([:positive]))
        ),
      request_id:
        Keyword.get(
          opts,
          :request_id,
          "req-" <> Integer.to_string(System.unique_integer([:positive]))
        )
    }
  end
end
