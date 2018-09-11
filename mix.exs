defmodule LibclusterEtcd.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_etcd,
      version: "1.0.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: "https://github.com/dkataskin/libcluster_etcd",
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

  defp description() do
    "etcd clustering strategy for libcluster"
  end

  defp package() do
    [
      name: "libcluster_etcd",
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* src),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/dkataskin/libcluster_etcd"}
    ]
  end
end
