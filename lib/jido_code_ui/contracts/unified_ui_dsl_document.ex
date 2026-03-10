defmodule JidoCodeUi.Contracts.UnifiedUiDslDocument do
  @moduledoc """
  Versioned unified-ui DSL document consumed by the compiler.
  """

  @type t :: %__MODULE__{
          dsl_version: String.t() | nil,
          root: map(),
          metadata: map(),
          custom_nodes: [String.t()]
        }

  defstruct dsl_version: nil,
            root: %{},
            metadata: %{},
            custom_nodes: []

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      dsl_version: string_field(attrs, :dsl_version),
      root: map_field(attrs, :root),
      metadata: map_field(attrs, :metadata),
      custom_nodes: string_list_field(attrs, :custom_nodes)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{} = document) do
    %{
      dsl_version: document.dsl_version,
      root: document.root,
      metadata: document.metadata,
      custom_nodes: document.custom_nodes
    }
  end

  def to_map(document) when is_map(document), do: document
  def to_map(_document), do: %{}

  defp string_list_field(attrs, key) do
    case get_value(attrs, key) do
      values when is_list(values) ->
        values
        |> Enum.map(&string_value/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp string_field(attrs, key) do
    attrs
    |> get_value(key)
    |> string_value()
  end

  defp string_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp string_value(nil), do: nil

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
