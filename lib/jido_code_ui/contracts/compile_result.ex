defmodule JidoCodeUi.Contracts.CompileResult do
  @moduledoc """
  Deterministic server-authoritative compile output contract.
  """

  alias JidoCodeUi.Contracts.UnifiedIurDocument
  alias JidoCodeUi.Contracts.UnifiedUiDslDocument

  @type t :: %__MODULE__{
          compile_authority: String.t(),
          dsl_version: String.t() | nil,
          iur_version: String.t() | nil,
          iur_document: UnifiedIurDocument.t(),
          iur_hash: String.t() | nil,
          diagnostics: [map()],
          dsl_document: UnifiedUiDslDocument.t(),
          compile_opts: keyword()
        }

  defstruct compile_authority: "server",
            dsl_version: nil,
            iur_version: nil,
            iur_document: %UnifiedIurDocument{},
            iur_hash: nil,
            diagnostics: [],
            dsl_document: %UnifiedUiDslDocument{},
            compile_opts: []

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      compile_authority: string_field(attrs, :compile_authority) || "server",
      dsl_version: string_field(attrs, :dsl_version),
      iur_version: string_field(attrs, :iur_version),
      iur_document: iur_document_field(get_value(attrs, :iur_document)),
      iur_hash: string_field(attrs, :iur_hash),
      diagnostics: diagnostics_field(get_value(attrs, :diagnostics)),
      dsl_document: dsl_document_field(get_value(attrs, :dsl_document)),
      compile_opts: compile_opts_field(get_value(attrs, :compile_opts))
    }
  end

  def new(_attrs), do: %__MODULE__{}

  defp iur_document_field(%UnifiedIurDocument{} = document), do: document
  defp iur_document_field(document) when is_map(document), do: UnifiedIurDocument.new(document)
  defp iur_document_field(_document), do: %UnifiedIurDocument{}

  defp dsl_document_field(%UnifiedUiDslDocument{} = document), do: document

  defp dsl_document_field(document) when is_map(document),
    do: UnifiedUiDslDocument.new(document)

  defp dsl_document_field(_document), do: %UnifiedUiDslDocument{}

  defp diagnostics_field(values) when is_list(values) do
    values
    |> Enum.filter(&is_map/1)
  end

  defp diagnostics_field(_values), do: []

  defp compile_opts_field(values) when is_list(values), do: values
  defp compile_opts_field(_values), do: []

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
