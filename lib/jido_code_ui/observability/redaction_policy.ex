defmodule JidoCodeUi.Observability.RedactionPolicy do
  @moduledoc """
  Centralized redaction policy for telemetry payloads.
  """

  @redacted_value "[REDACTED]"
  @policy_version "v1"

  @sensitive_exact_keys MapSet.new([
                          "prompt",
                          "code",
                          "contents",
                          "secret",
                          "token",
                          "api_key",
                          "access_token",
                          "refresh_token",
                          "authorization"
                        ])

  @sensitive_suffixes ["_token", "_secret", "_api_key", "_apikey", "_password", "_passphrase"]

  @miss_patterns [
    ~r/\bBearer\s+[A-Za-z0-9\-._~+\/]+=*/i,
    ~r/\b(api[_-]?key|token|secret)\s*[:=]\s*[A-Za-z0-9\-._~+\/=]{8,}/i,
    ~r/-----BEGIN (?:RSA|EC|OPENSSH|PRIVATE) KEY-----/,
    ~r/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/
  ]

  @type report :: %{
          redaction_applied: boolean(),
          redacted_fields: [String.t()],
          redaction_policy_version: String.t(),
          misses: [String.t()]
        }

  @spec redact(map()) :: {map(), report()}
  def redact(metadata) when is_map(metadata) do
    {redacted, redacted_fields} = redact_value(metadata, [])

    misses =
      redacted
      |> collect_miss_paths([])
      |> Enum.uniq()
      |> Enum.sort()

    report = %{
      redaction_applied: redacted_fields != [],
      redacted_fields: redacted_fields |> Enum.uniq() |> Enum.sort(),
      redaction_policy_version: @policy_version,
      misses: misses
    }

    {
      redacted
      |> Map.put(:redaction_applied, report.redaction_applied)
      |> Map.put(:redaction_policy_version, @policy_version),
      report
    }
  end

  def redact(metadata) do
    {
      metadata,
      %{
        redaction_applied: false,
        redacted_fields: [],
        redaction_policy_version: @policy_version,
        misses: []
      }
    }
  end

  defp redact_value(value, path) when is_map(value) and not is_struct(value) do
    Enum.reduce(value, {%{}, []}, fn {key, nested_value}, {acc_map, acc_fields} ->
      normalized_key = normalized_key(key)
      child_path = path ++ [to_string(key)]

      if sensitive_key?(normalized_key) do
        {Map.put(acc_map, key, @redacted_value), [Enum.join(child_path, ".") | acc_fields]}
      else
        {redacted_nested, nested_fields} = redact_value(nested_value, child_path)
        {Map.put(acc_map, key, redacted_nested), acc_fields ++ nested_fields}
      end
    end)
  end

  defp redact_value(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {item, index}, {acc_list, acc_fields} ->
      {redacted_item, nested_fields} = redact_value(item, path ++ ["[#{index}]"])
      {acc_list ++ [redacted_item], acc_fields ++ nested_fields}
    end)
  end

  defp redact_value(value, _path), do: {value, []}

  defp collect_miss_paths(value, path) when is_map(value) and not is_struct(value) do
    Enum.flat_map(value, fn {key, nested_value} ->
      collect_miss_paths(nested_value, path ++ [to_string(key)])
    end)
  end

  defp collect_miss_paths(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      collect_miss_paths(item, path ++ ["[#{index}]"])
    end)
  end

  defp collect_miss_paths(value, path) when is_binary(value) do
    if value == @redacted_value do
      []
    else
      if Enum.any?(@miss_patterns, &Regex.match?(&1, value)) do
        [Enum.join(path, ".")]
      else
        []
      end
    end
  end

  defp collect_miss_paths(_value, _path), do: []

  defp normalized_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalized_key()
  defp normalized_key(key) when is_binary(key), do: key |> String.trim() |> String.downcase()
  defp normalized_key(_key), do: ""

  defp sensitive_key?(key) do
    MapSet.member?(@sensitive_exact_keys, key) or
      Enum.any?(@sensitive_suffixes, &String.ends_with?(key, &1))
  end
end
