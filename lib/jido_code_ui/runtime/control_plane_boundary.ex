defmodule JidoCodeUi.Runtime.ControlPlaneBoundary do
  @moduledoc """
  Enforces startup wiring and control-plane boundary rules.
  """

  alias JidoCodeUi.Observability.Telemetry
  alias JidoCodeUi.Session.RuntimeAgent
  alias JidoCodeUi.TypedError

  @required_runtime_modules [
    JidoCodeUi.Runtime.Substrate,
    JidoCodeUi.Security.Policy,
    JidoCodeUi.Services.UiOrchestrator,
    JidoCodeUi.Services.DslCompiler,
    JidoCodeUi.Services.IurRenderer,
    JidoCodeUi.Session.RuntimeAgent
  ]

  @default_ownership %{
    JidoCodeUi.Runtime.Substrate => :transport,
    JidoCodeUi.Security.Policy => :runtime,
    JidoCodeUi.Services.UiOrchestrator => :runtime,
    JidoCodeUi.Services.DslCompiler => :runtime,
    JidoCodeUi.Services.IurRenderer => :ui,
    JidoCodeUi.Session.RuntimeAgent => :runtime
  }

  @session_mutation_authority [JidoCodeUi.Session.RuntimeAgent]

  @spec required_runtime_modules() :: [module()]
  def required_runtime_modules do
    @required_runtime_modules
  end

  @spec default_ownership() :: %{module() => :transport | :runtime | :ui}
  def default_ownership do
    @default_ownership
  end

  @spec session_mutation_authority() :: [module()]
  def session_mutation_authority do
    @session_mutation_authority
  end

  @spec validate_runtime_wiring([module()], %{module() => atom()}) ::
          :ok | {:error, TypedError.t()}
  def validate_runtime_wiring(runtime_modules, ownership_map \\ @default_ownership)

  def validate_runtime_wiring(runtime_modules, ownership_map)
      when is_list(runtime_modules) and is_map(ownership_map) do
    with :ok <- ensure_required_children(runtime_modules),
         :ok <- ensure_startup_order(runtime_modules),
         :ok <- ensure_ownership_assignments(runtime_modules, ownership_map),
         :ok <- ensure_session_runtime_authority(ownership_map) do
      :ok
    else
      {:error, %TypedError{} = typed_error} = error ->
        emit_boundary_denied(typed_error)
        error
    end
  end

  @spec authorize_session_mutation(module()) :: :ok | {:error, TypedError.t()}
  def authorize_session_mutation(module) when is_atom(module) do
    if module in @session_mutation_authority do
      :ok
    else
      error =
        TypedError.boundary(
          :session_authority_violation,
          "Only session runtime authority modules can mutate session state",
          stage: "session_mutation_authority",
          details: %{
            module: inspect(module),
            allowed: Enum.map(@session_mutation_authority, &inspect/1)
          }
        )

      emit_boundary_denied(error)
      {:error, error}
    end
  end

  defp ensure_required_children(runtime_modules) do
    missing = Enum.reject(@required_runtime_modules, &(&1 in runtime_modules))

    if missing == [] do
      :ok
    else
      {:error,
       TypedError.boundary(
         :missing_required_child,
         "Runtime wiring is missing required startup children",
         details: %{missing_modules: Enum.map(missing, &inspect/1)}
       )}
    end
  end

  defp ensure_startup_order(runtime_modules) do
    with :ok <-
           assert_before(
             runtime_modules,
             JidoCodeUi.Runtime.Substrate,
             JidoCodeUi.Services.UiOrchestrator
           ),
         :ok <-
           assert_before(
             runtime_modules,
             JidoCodeUi.Security.Policy,
             JidoCodeUi.Services.UiOrchestrator
           ),
         :ok <-
           assert_before(
             runtime_modules,
             JidoCodeUi.Services.DslCompiler,
             JidoCodeUi.Services.IurRenderer
           ) do
      :ok
    end
  end

  defp assert_before(runtime_modules, first, second) do
    first_index = Enum.find_index(runtime_modules, &(&1 == first))
    second_index = Enum.find_index(runtime_modules, &(&1 == second))

    cond do
      is_nil(first_index) or is_nil(second_index) ->
        {:error,
         TypedError.boundary(
           :startup_child_order_violation,
           "Runtime wiring order cannot be validated due to missing child modules",
           details: %{first: inspect(first), second: inspect(second)}
         )}

      first_index < second_index ->
        :ok

      true ->
        {:error,
         TypedError.boundary(
           :startup_child_order_violation,
           "Runtime startup order violates required dependency ordering",
           details: %{first: inspect(first), second: inspect(second)}
         )}
    end
  end

  defp ensure_ownership_assignments(runtime_modules, ownership_map) do
    missing =
      runtime_modules
      |> Enum.filter(&(&1 in @required_runtime_modules))
      |> Enum.reject(&Map.has_key?(ownership_map, &1))

    if missing == [] do
      :ok
    else
      {:error,
       TypedError.boundary(
         :missing_control_plane_assignment,
         "Runtime wiring has modules without control-plane ownership assignments",
         details: %{missing_assignments: Enum.map(missing, &inspect/1)}
       )}
    end
  end

  defp ensure_session_runtime_authority(ownership_map) do
    case Map.get(ownership_map, RuntimeAgent) do
      :runtime ->
        :ok

      actual ->
        {:error,
         TypedError.boundary(
           :session_authority_violation,
           "Session runtime owner must map to runtime control plane",
           details: %{module: inspect(RuntimeAgent), expected: :runtime, actual: actual}
         )}
    end
  end

  defp emit_boundary_denied(%TypedError{} = typed_error) do
    Telemetry.emit("runtime.startup.boundary_denied", %{
      error_code: typed_error.error_code,
      category: typed_error.category,
      stage: typed_error.stage,
      correlation_id: typed_error.correlation_id,
      request_id: typed_error.request_id,
      details: typed_error.details
    })
  end
end
