defmodule JidoCodeUi.Contracts.UnifiedIurDocument do
  @moduledoc """
  Canonical `unified-iur` document produced by server-side compilation.
  """

  @type t :: %__MODULE__{
          iur_version: String.t() | nil,
          dsl_version: String.t() | nil,
          root: map(),
          metadata: map()
        }

  defstruct iur_version: nil,
            dsl_version: nil,
            root: %{},
            metadata: %{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      iur_version: string_field(attrs, :iur_version),
      dsl_version: string_field(attrs, :dsl_version),
      root: map_field(attrs, :root),
      metadata: map_field(attrs, :metadata)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{} = document) do
    %{
      "iur_version" => document.iur_version,
      "dsl_version" => document.dsl_version,
      "root" => document.root,
      "metadata" => document.metadata
    }
  end

  def to_map(document) when is_map(document), do: document
  def to_map(_document), do: %{}

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
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
