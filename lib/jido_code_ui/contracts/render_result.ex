defmodule JidoCodeUi.Contracts.RenderResult do
  @moduledoc """
  Canonical render output contract produced by `JidoCodeUi.Services.IurRenderer`.
  """

  @type t :: %__MODULE__{
          rendered: boolean(),
          projection: map(),
          continuity: map(),
          event_projection: map(),
          render_metadata: map()
        }

  defstruct rendered: false,
            projection: %{},
            continuity: %{},
            event_projection: %{},
            render_metadata: %{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      rendered: get_value(attrs, :rendered) == true,
      projection: map_field(attrs, :projection),
      continuity: map_field(attrs, :continuity),
      event_projection: map_field(attrs, :event_projection),
      render_metadata: map_field(attrs, :render_metadata)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp map_field(attrs, key) do
    case get_value(attrs, key) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp get_value(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        nil
    end
  end
end
