defmodule JidoCodeUi.Contracts.OrchestratorResult do
  @moduledoc """
  Canonical success output contract produced by `JidoCodeUi.Services.UiOrchestrator`.
  """

  alias JidoCodeUi.Contracts.CompileResult
  alias JidoCodeUi.Contracts.RenderResult
  alias JidoCodeUi.Contracts.UiSessionSnapshot

  @type t :: %__MODULE__{
          status: atom(),
          route_key: String.t() | nil,
          stage_trace: [atom()],
          envelope_kind: atom() | nil,
          continuity: map(),
          policy: map(),
          compile: CompileResult.t(),
          session: UiSessionSnapshot.t(),
          render: RenderResult.t()
        }

  defstruct status: :ok,
            route_key: nil,
            stage_trace: [],
            envelope_kind: nil,
            continuity: %{},
            policy: %{},
            compile: %CompileResult{},
            session: %UiSessionSnapshot{},
            render: %RenderResult{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      status: status_field(get_value(attrs, :status)),
      route_key: string_field(attrs, :route_key),
      stage_trace: stage_trace_field(get_value(attrs, :stage_trace)),
      envelope_kind: envelope_kind_field(get_value(attrs, :envelope_kind)),
      continuity: map_field(attrs, :continuity),
      policy: map_field(attrs, :policy),
      compile: compile_field(get_value(attrs, :compile)),
      session: session_field(get_value(attrs, :session)),
      render: render_field(get_value(attrs, :render))
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp status_field(value) when is_atom(value), do: value

  defp status_field(value) when is_binary(value) do
    case String.trim(value) do
      "ok" -> :ok
      "error" -> :error
      _ -> :ok
    end
  end

  defp status_field(_value), do: :ok

  defp stage_trace_field(values) when is_list(values) do
    values
    |> Enum.map(&stage_atom/1)
    |> Enum.reject(&is_nil/1)
  end

  defp stage_trace_field(_values), do: []

  defp stage_atom(value) when is_atom(value), do: value

  defp stage_atom(value) when is_binary(value) do
    case String.trim(value) do
      "validate" -> :validate
      "policy" -> :policy
      "compile" -> :compile
      "session" -> :session
      "render" -> :render
      _ -> nil
    end
  end

  defp stage_atom(_value), do: nil

  defp envelope_kind_field(value) when is_atom(value), do: value

  defp envelope_kind_field(value) when is_binary(value) do
    case String.trim(value) do
      "ui_command" -> :ui_command
      "widget_ui_event" -> :widget_ui_event
      _ -> nil
    end
  end

  defp envelope_kind_field(_value), do: nil

  defp compile_field(%CompileResult{} = compile), do: compile
  defp compile_field(compile) when is_map(compile), do: CompileResult.new(compile)
  defp compile_field(_compile), do: %CompileResult{}

  defp session_field(%UiSessionSnapshot{} = session), do: session
  defp session_field(session) when is_map(session), do: UiSessionSnapshot.new(session)
  defp session_field(_session), do: %UiSessionSnapshot{}

  defp render_field(%RenderResult{} = render), do: render
  defp render_field(render) when is_map(render), do: RenderResult.new(render)
  defp render_field(_render), do: %RenderResult{}

  defp string_field(attrs, key) do
    attrs
    |> get_value(key)
    |> string_value()
  end

  defp string_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp string_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> string_value()
  end

  defp string_value(_value), do: nil

  defp map_field(attrs, key) do
    case get_value(attrs, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
