defmodule JidoCodeUi.Services.DslCompiler do
  @moduledoc """
  Startup-ready compiler service placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupLifecycle

  @ready_child_id :dsl_compiler

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec compile(map(), keyword()) :: {:ok, map()}
  def compile(dsl_document, opts \\ []) when is_list(opts) do
    {:ok,
     %{
       compile_authority: "server",
       dsl_document: dsl_document,
       compile_opts: opts
     }}
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end
end
