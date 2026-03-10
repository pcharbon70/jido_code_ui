defmodule JidoCodeUi.Contracts.UiSessionSnapshot do
  @moduledoc """
  In-memory authoritative UI session snapshot contract.
  """

  @type t :: %__MODULE__{
          schema_version: String.t() | nil,
          snapshot_kind: String.t() | nil,
          session_id: String.t() | nil,
          route_key: String.t() | nil,
          continuity: map(),
          compile: map(),
          render: map(),
          active_iur_hash: String.t() | nil,
          replay: map(),
          rollback: map() | nil,
          metadata: map(),
          revision: non_neg_integer(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct schema_version: nil,
            snapshot_kind: nil,
            session_id: nil,
            route_key: nil,
            continuity: %{},
            compile: %{},
            render: %{},
            active_iur_hash: nil,
            replay: %{},
            rollback: nil,
            metadata: %{},
            revision: 0,
            created_at: nil,
            updated_at: nil

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      schema_version: string_field(attrs, :schema_version),
      snapshot_kind: string_field(attrs, :snapshot_kind),
      session_id: string_field(attrs, :session_id),
      route_key: string_field(attrs, :route_key),
      continuity: map_field(attrs, :continuity),
      compile: map_field(attrs, :compile),
      render: map_field(attrs, :render),
      active_iur_hash: string_field(attrs, :active_iur_hash),
      replay: map_field(attrs, :replay),
      rollback: rollback_field(attrs),
      metadata: map_field(attrs, :metadata),
      revision: integer_field(attrs, :revision),
      created_at: datetime_field(attrs, :created_at),
      updated_at: datetime_field(attrs, :updated_at)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp rollback_field(attrs) do
    case get_value(attrs, :rollback) do
      nil -> nil
      value when is_map(value) -> value
      _ -> nil
    end
  end

  defp datetime_field(attrs, key) do
    case get_value(attrs, key) do
      %DateTime{} = value -> value
      _ -> nil
    end
  end

  defp integer_field(attrs, key) do
    case get_value(attrs, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
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
