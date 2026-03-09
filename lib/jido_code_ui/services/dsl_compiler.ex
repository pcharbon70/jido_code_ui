defmodule JidoCodeUi.Services.DslCompiler do
  @moduledoc """
  Startup-ready compiler service placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :dsl_compiler

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec compile(map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def compile(dsl_document, opts \\ []) when is_list(opts) do
    with :ok <- StartupGuard.ensure_ready("dsl_compile", %{operation: "compile"}) do
      if force_compile_failure?(dsl_document) do
        {:error,
         TypedError.ingress("dsl_compile_failed", "DSL compile failed",
           category: "compile",
           stage: "dsl_compile",
           details: %{reason: "forced_failure"},
           correlation_id: Keyword.get(opts, :correlation_id),
           request_id: Keyword.get(opts, :request_id)
         )}
      else
        {:ok,
         %{
           compile_authority: "server",
           dsl_document: dsl_document,
           compile_opts: opts
         }}
      end
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp force_compile_failure?(dsl_document) do
    get_value(dsl_document, :force_error) == true or
      get_in(dsl_document, [:command, :payload, :force_compile_error]) == true
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_value(_map, _key), do: nil
end
