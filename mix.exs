defmodule LibclusterEtcd.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_etcd,
      version: "1.0.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger]
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.0.0"},
    ]
  end
end
