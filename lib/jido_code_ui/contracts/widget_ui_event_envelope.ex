defmodule JidoCodeUi.Contracts.WidgetUiEventEnvelope do
  @moduledoc """
  Canonical admitted widget UI event envelope for runtime dispatch.
  """

  @type t :: %__MODULE__{
          type: String.t() | nil,
          widget_id: String.t() | nil,
          widget_kind: String.t() | nil,
          timestamp: String.t() | nil,
          data: map(),
          session_id: String.t() | nil,
          route_key: String.t() | nil,
          render_token: String.t() | nil,
          correlation_id: String.t() | nil,
          request_id: String.t() | nil
        }

  defstruct type: nil,
            widget_id: nil,
            widget_kind: nil,
            timestamp: nil,
            data: %{},
            session_id: nil,
            route_key: nil,
            render_token: nil,
            correlation_id: nil,
            request_id: nil

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      type: string_field(attrs, :type),
      widget_id: string_field(attrs, :widget_id),
      widget_kind: string_field(attrs, :widget_kind),
      timestamp: string_field(attrs, :timestamp),
      data: map_field(attrs, :data),
      session_id: string_field(attrs, :session_id),
      route_key: string_field(attrs, :route_key),
      render_token: string_field(attrs, :render_token),
      correlation_id: string_field(attrs, :correlation_id),
      request_id: string_field(attrs, :request_id)
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp string_field(attrs, key) do
    case get_value(attrs, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      nil ->
        nil

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
