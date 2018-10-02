# LibclusterEtcd

Etcd strategy for libcluster. It utilisez Etcd v2 API.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `libcluster_etcd` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:libcluster_etcd, "~> 1.0.0"}
  ]
end
```

## Configuration

Minimal configuration is list of etcd nodes ```etcd_nodes``` and directory name ```directory```:
```elixir
config :libcluster,
  topologies: [
    etcd: [
      strategy: LibclusterEtcd.Strategy,
      config: [
        etcd_nodes: ["http://10.0.0.1:2379", "http://10.0.0.2:2379"],
        directory: "cluster"
      ]
    ]
  ]
```

In addition to that you can control polling interval, ttl of the keys and ttl refresh interval, ```httpc``` options:
```elixir
config :libcluster,
  topologies: [
    etcd: [
      strategy: LibclusterEtcd.Strategy,
      config: [
        etcd_nodes: ["http://10.0.0.1:2379", "http://10.0.0.2:2379"],
        directory: "cluster",
        ttl: 10_000,
        ttl_refresh_interval: 5_000,
        polling_interval: 5_000
      ]
    ]
  ]
```

|       Parameter      | Required? |                                    Default Value                                    |                               Description                               |   |
|:--------------------:|:---------:|:-----------------------------------------------------------------------------------:|:-----------------------------------------------------------------------:|---|
|      etcd_nodes      |    Yes    |                                                                                     | List of etcd nodes                                                      |   |
|       directory      |    Yes    |                                                                                     | Etcd directory to store cluster nodes registrations                     |   |
|          ttl         |     No    |                                        10_000                                       | Node's registration ttl in ms. Uses etcd ttl to keep key alive.         |   |
| ttl_refresh_interval |     No    |                                        5_000                                        | How often to refresh ttl of a key, ms. Should be less than ```ttl```.   |   |
|   polling_interval   |     No    |                                        5_000                                        | How often to scan ```directory``` and connect and disconnect nodes, ms. |   |
|       http_opts      |     No    | [  timeout: 10_000,  connect_timeout: 2_000,  autoredirect: false,  relaxed: true ] | ```httpc``` options used for each request to etcd.                      |   |
|                      |           |                                                                                     |                                                                         |   |

```ttl```, ```ttl_refresh_interval```, ```timeout``` and ```connect_timeout``` should be carefully chosen. If ```connect_timeout``` is greater or equal to ```ttl``` then most likely etcd key will expire before it will be renewed if etcd client tries to connect to a dead node.