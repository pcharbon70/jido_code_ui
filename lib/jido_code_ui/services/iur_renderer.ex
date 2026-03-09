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
      if force_render_failure?(iur_document) do
        {:error,
         TypedError.ingress("iur_render_failed", "IUR render failed",
           category: "render",
           stage: "iur_render",
           details: %{reason: "forced_failure"},
           correlation_id: Keyword.get(opts, :correlation_id),
           request_id: Keyword.get(opts, :request_id)
         )}
      else
        {:ok,
         %{
           rendered: true,
           projection: iur_document,
           render_opts: opts
         }}
      end
    end
  end

  @impl true
  def init(_opts) do
    StartupLifecycle.mark_child_ready(@ready_child_id)
    {:ok, %{}}
  end

  defp force_render_failure?(iur_document) do
    get_value(iur_document, :force_error) == true or
      get_in(iur_document, [
        :compile_result,
        :dsl_document,
        :command,
        :payload,
        :force_render_error
      ]) == true or
      get_in(iur_document, [
        :compile_result,
        :dsl_document,
        :root,
        :props,
        :force_render_error
      ]) == true
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp get_value(_map, _key), do: nil
end
