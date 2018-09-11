defmodule LibclusterEtcd.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_etcd,
      version: "1.0.1",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: "https://github.com/dkataskin/libcluster_etcd",
      docs: docs(),
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
      {:jason, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description() do
    "etcd clustering strategy for libcluster"
  end

  defp package() do
    [
      name: "libcluster_etcd",
      maintainers: ["Dmitriy Kataskin"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/dkataskin/libcluster_etcd"}
    ]
  end

  defp docs do
    [
      main: "readme",
      formatter_opts: [gfm: true],
      extras: [
        "README.md"
      ]
    ]
  end
end
