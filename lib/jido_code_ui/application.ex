defmodule JidoCodeUi.Application do
  @moduledoc false

  use Application
  alias JidoCodeUi.TypedError
  alias JidoCodeUi.Runtime.ControlPlaneBoundary

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

  @spec validate_runtime_wiring([module()], %{module() => atom()}) ::
          :ok | {:error, TypedError.t()}
  def validate_runtime_wiring(
        runtime_modules \\ runtime_child_order(),
        ownership_map \\ ControlPlaneBoundary.default_ownership()
      ) do
    ControlPlaneBoundary.validate_runtime_wiring(runtime_modules, ownership_map)
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

  @spec start_root([Supervisor.child_spec() | {module(), keyword()} | module()], keyword()) ::
          {:ok, pid()} | {:error, TypedError.t()}
  def start_root(children \\ runtime_children(), opts \\ supervisor_opts()) do
    try do
      case Supervisor.start_link(children, opts) do
        {:ok, _pid} = ok ->
          ok

        {:error, reason} ->
          {:error, TypedError.classify_startup_failure(reason, stage: "application_start")}
      end
    catch
      :exit, reason ->
        {:error, TypedError.classify_startup_failure(reason, stage: "application_start")}
    end
  end

  @impl true
  def start(_type, _args) do
    with :ok <- validate_runtime_wiring() do
      start_root()
    end
  end
end
