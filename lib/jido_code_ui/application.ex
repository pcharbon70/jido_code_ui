defmodule JidoCodeUi.Application do
  @moduledoc false

  use Application
  alias JidoCodeUi.TypedError

  @runtime_ready_children [
    :runtime_substrate,
    :security_policy,
    :ui_orchestrator,
    :dsl_compiler,
    :iur_renderer,
    :session_runtime_agent
  ]

  @spec runtime_ready_children() :: [atom()]
  def runtime_ready_children do
    @runtime_ready_children
  end

  @spec runtime_children() :: [Supervisor.child_spec() | {module(), keyword()} | module()]
  def runtime_children do
    [
      {JidoCodeUi.Runtime.StartupLifecycle, expected_children: runtime_ready_children()},
      JidoCodeUi.Runtime.Substrate,
      JidoCodeUi.Security.Policy,
      JidoCodeUi.Services.UiOrchestrator,
      JidoCodeUi.Services.DslCompiler,
      JidoCodeUi.Services.IurRenderer,
      JidoCodeUi.Session.RuntimeAgent
    ]
  end

  @spec runtime_child_order() :: [module()]
  def runtime_child_order do
    Enum.map(runtime_children(), fn
      {module, _opts} -> module
      module when is_atom(module) -> module
    end)
  end

  @spec supervisor_opts() :: keyword()
  def supervisor_opts do
    [
      strategy: :one_for_one,
      name: JidoCodeUi.Supervisor,
      max_restarts: 5,
      max_seconds: 30
    ]
  end

  @impl true
  def start(_type, _args) do
    case Supervisor.start_link(runtime_children(), supervisor_opts()) do
      {:ok, _pid} = ok ->
        ok

      {:error, reason} ->
        {:error,
         TypedError.startup(:root_supervisor_start_failed, reason,
           stage: "application_start",
           retryable: false,
           message: "Failed to start jido_code_ui root supervisor"
         )}
    end
  end
end
