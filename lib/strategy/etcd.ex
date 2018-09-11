defmodule LibclusterEtcd.Strategy do
  use Cluster.Strategy
  use GenServer

  import Cluster.Logger

  alias Cluster.Strategy.State
  alias LibclusterEtcd.EtcdClient

  @default_polling_interval 5_000
  @default_ttl_refresh_interval 5_000
  @default_ttl 10

  @impl Cluster.Strategy
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init([%State{config: config, topology: topology} = state]) do
    host = Keyword.fetch!(config, :etcd_host)
    port = Keyword.get(config, :etcd_port, 2379)
    dir = Keyword.fetch!(config, :directory)

    etcd_server_url = etcd_server_url(host, port)
    ttl = Keyword.get(config, :ttl, @default_ttl)
    info(topology, "registering node #{inspect(Node.self())} in bucket #{dir}")
    {:ok, key} = register(etcd_server_url, dir, ttl)

    info(
      topology,
      "node #{inspect(Node.self())} registered with key #{inspect(key)} in bucket #{dir}"
    )

    config = config |> Keyword.put(:etcd_server_url, etcd_server_url)

    state = %State{
      state
      | config: config,
        meta: %{
          registered_key: key,
          nodes: MapSet.new()
        }
    }

    {:ok, state, 0}
  end

  @impl GenServer
  def handle_info(:timeout, %State{} = state) do
    {:noreply, state} = handle_info(:refresh_ttl, state)
    handle_info(:check_nodes, state)
  end

  @impl GenServer
  def handle_info(:check_nodes, %State{config: config, topology: topology} = state) do
    debug(topology, "checking nodes")

    connect = state.connect
    disconnect = state.disconnect
    list_nodes = state.list_nodes

    etcd_server_url = Keyword.fetch!(config, :etcd_server_url)
    dir = Keyword.fetch!(config, :directory)

    with {:ok, nodes} <- list_nodes(etcd_server_url, dir),
         nodes_set <- nodes |> MapSet.new(),
         new_nodes <- nodes_set |> MapSet.difference(state.meta.nodes) |> MapSet.to_list(),
         :ok <- debug(topology, fn -> "new nodes: #{inspect(new_nodes)}" end),
         removed_nodes <- state.meta.nodes |> MapSet.difference(nodes_set) |> MapSet.to_list(),
         :ok <- debug(topology, fn -> "removed nodes: #{inspect(removed_nodes)}" end) do
      failed_to_disconnect =
        with :ok <-
               Cluster.Strategy.disconnect_nodes(topology, disconnect, list_nodes, removed_nodes) do
          []
        else
          {:error, error_nodes} ->
            error(topology, "couldn't disconnect from #{inspect(error_nodes)}")
            error_nodes |> Enum.map(fn {node, _} -> node end)

          error ->
            error(topology, "#{inspect(error)}")
            []
        end

      failed_to_connect =
        with :ok <- Cluster.Strategy.connect_nodes(topology, connect, list_nodes, new_nodes) do
          []
        else
          {:error, error_nodes} ->
            error(topology, "couldn't connect to #{inspect(error_nodes)}")
            error_nodes |> Enum.map(fn {node, _} -> node end)

          error ->
            error(topology, "#{inspect(error)}")
            []
        end

      nodes_set =
        failed_to_disconnect
        |> Enum.reduce(nodes_set, fn node, acc ->
          acc |> MapSet.put(node)
        end)

      nodes_set =
        failed_to_connect
        |> Enum.reduce(nodes_set, fn node, acc ->
          acc |> MapSet.delete(node)
        end)

      check_nodes(state.config)
      {:noreply, %{state | meta: state.meta |> Map.put(:nodes, nodes_set)}}
    else
      {:error, reason} ->
        error(topology, reason)
        check_nodes(config)
        {:noreply, state}

      error ->
        error(topology, "#{inspect(error)}")
        check_nodes(config)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(
        :refresh_ttl,
        %State{config: config, topology: topology, meta: %{registered_key: key}} = state
      ) do
    debug(topology, fn -> "refreshing ttl for key #{inspect(key)}" end)
    etcd_server_url = Keyword.fetch!(config, :etcd_server_url)
    dir = Keyword.fetch!(config, :directory)
    ttl = Keyword.get(config, :ttl, @default_ttl)

    EtcdClient.refresh_ttl(etcd_server_url, dir, key, ttl, true)
    refresh_ttl(config)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    etcd_server_url = Keyword.fetch!(state.config, :etcd_server_url)
    dir = Keyword.fetch!(state.config, :directory)
    EtcdClient.delete(etcd_server_url, dir, state.meta.registered_key)

    debug(state.topology, "terminating with reason: #{inspect(reason)}")
  end

  def register(etcd_server_url, dir, ttl) do
    EtcdClient.push(etcd_server_url, dir, Node.self() |> to_string(), ttl)
  end

  def list_nodes(etcd_server_url, dir) do
    with {:ok, key_value_pairs} <- EtcdClient.list(etcd_server_url, dir) do
      nodes =
        key_value_pairs
        |> Enum.reduce([], fn {_key, value}, acc ->
          if String.equivalent?(value, "") do
            acc
          else
            [value |> String.to_atom() | acc]
          end
        end)
        |> Enum.reject(&(&1 === Node.self()))

      {:ok, nodes}
    end
  end

  defp check_nodes(config) do
    polling_interval = Keyword.get(config, :polling_interval, @default_polling_interval)
    Process.send_after(self(), :check_nodes, polling_interval)
  end

  defp refresh_ttl(config) do
    ttl_interval = Keyword.get(config, :ttl_refresh_interval, @default_ttl_refresh_interval)
    Process.send_after(self(), :refresh_ttl, ttl_interval)
  end

  defp etcd_server_url(host, port) when is_binary(host) and is_integer(port) do
    host
    |> cleanup_trailing_slash()
    |> URI.parse()
    |> uri_check_scheme()
    |> uri_check_host()
    |> uri_set_port(port)
    |> URI.to_string()
  end

  defp cleanup_trailing_slash(host) do
    if String.ends_with?(host, "/") do
      host |> String.slice(0..-2)
    else
      host
    end
  end

  defp uri_check_scheme(%URI{scheme: nil} = uri), do: %URI{uri | scheme: "http"}
  defp uri_check_scheme(%URI{scheme: _scheme} = uri), do: uri

  defp uri_check_host(%URI{host: nil} = uri), do: %URI{uri | host: uri.path, path: nil}
  defp uri_check_host(%URI{host: _host} = uri), do: uri

  defp uri_set_port(%URI{} = uri, port) when is_integer(port), do: %URI{uri | port: port}
end
