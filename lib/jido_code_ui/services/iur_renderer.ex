defmodule JidoCodeUi.Services.IurRenderer do
  @moduledoc """
  Startup-ready renderer service placeholder.
  """

  use GenServer

  alias JidoCodeUi.Runtime.StartupGuard
  alias JidoCodeUi.Runtime.StartupLifecycle
  alias JidoCodeUi.TypedError

  @ready_child_id :iur_renderer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec render(map(), keyword()) :: {:ok, map()} | {:error, TypedError.t()}
  def render(iur_document, opts \\ []) when is_list(opts) do
    with :ok <- StartupGuard.ensure_ready("iur_render", %{operation: "render"}) do
      {:ok,
       %{
         rendered: true,
         projection: iur_document,
         render_opts: opts
       }}
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end
end
