defmodule LibclusterEtcdTest do
  use ExUnit.Case
  doctest LibclusterEtcd

  test "greets the world" do
    assert LibclusterEtcd.hello() == :world
  end
end
