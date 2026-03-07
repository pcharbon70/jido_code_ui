defmodule JidoCodeUiTest do
  use ExUnit.Case
  doctest JidoCodeUi

  test "greets the world" do
    assert JidoCodeUi.hello() == :world
  end
end
