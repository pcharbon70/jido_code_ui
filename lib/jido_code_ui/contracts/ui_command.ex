defmodule JidoCodeUi.Contracts.UiCommand do
  @moduledoc """
  Canonical admitted command contract for runtime dispatch.
  """

  @type t :: %__MODULE__{
          command_type: String.t() | nil,
          session_id: String.t() | nil,
          correlation_id: String.t() | nil,
          request_id: String.t() | nil,
          payload: map()
        }

  defstruct command_type: nil,
            session_id: nil,
            correlation_id: nil,
            request_id: nil,
            payload: %{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_type: string_field(attrs, :command_type),
      session_id: string_field(attrs, :session_id),
      correlation_id: string_field(attrs, :correlation_id),
      request_id: string_field(attrs, :request_id),
      payload: map_field(attrs, :payload)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp string_field(attrs, key) do
    case get_value(attrs, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      value when is_atom(value) ->
        value
        |> Atom.to_string()
        |> string_field_value()

      _ ->
        nil
    end
  end

  defp string_field_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

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
