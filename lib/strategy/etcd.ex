defmodule LibclusterEtcd.Strategy do
  use Cluster.Strategy
  use GenServer

  import Cluster.Logger

  alias Cluster.Strategy.State
  alias LibclusterEtcd.EtcdClient

  @default_polling_interval 5_000
  @default_ttl_refresh_interval 5_000
  @default_ttl 10_000
  @etcd_default_port 2379

  @impl Cluster.Strategy
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init([%State{config: config, topology: topology} = state]) do
    # compatibility with 1.0.1
    host = Keyword.get(config, :etcd_host)
    port = Keyword.get(config, :etcd_port, 2379)
    etcd_nodes =
      if is_nil(host) do
        config 
        |> Keyword.fetch!(:etcd_nodes)
        |> Enum.map(&(etcd_server_url(&1)))
      else
        [etcd_server_url(host, port)]
      end

    if length(etcd_nodes) == 0 do
      raise "no etcd nodes specified in the config!"
    end

    dir = Keyword.fetch!(config, :directory)
    if length(etcd_nodes) == 0 do
      raise "no etcd directory specified in the config!"
    end

    ttl = Keyword.get(config, :ttl, @default_ttl)
    http_opts = Keyword.get(state.config, :http_opts, [])

    info(topology, "registering node #{inspect(Node.self())} in bucket #{dir}")
    {:ok, key} = register(etcd_nodes, dir, ttl, http_opts)

    info(
      topology,
      "node #{inspect(Node.self())} registered with key #{inspect(key)} in bucket #{dir}"
    )

    config = config |> Keyword.put(:etcd_nodes, etcd_nodes)

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

    etcd_nodes = Keyword.fetch!(config, :etcd_nodes)
    dir = Keyword.fetch!(config, :directory)
    http_opts = Keyword.get(state.config, :http_opts, [])

    with {:ok, nodes} <- list_nodes(etcd_nodes, dir, http_opts),
         nodes_set <- nodes |> MapSet.new(),
         new_nodes <- nodes_set |> MapSet.difference(state.meta.nodes) |> MapSet.to_list(),
         removed_nodes <- state.meta.nodes |> MapSet.difference(nodes_set) |> MapSet.to_list() do
      failed_to_disconnect =
        with :ok <-
               Cluster.Strategy.disconnect_nodes(topology, disconnect, list_nodes, removed_nodes) do
          debug(topology, "removed nodes: #{inspect(removed_nodes)}")
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
          debug(topology, "new nodes: #{inspect(new_nodes)}")
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

      send_check_nodes(state.config)
      {:noreply, %{state | meta: state.meta |> Map.put(:nodes, nodes_set)}}
    else
      {:error, reason} ->
        error(topology, reason)
        send_check_nodes(config)
        {:noreply, state}

      error ->
        error(topology, "#{inspect(error)}")
        send_check_nodes(config)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(
        :refresh_ttl,
        %State{config: config, topology: topology, meta: %{registered_key: key}} = state
      ) do
    debug(topology, "refreshing ttl for key #{inspect(key)}")
    etcd_nodes = Keyword.fetch!(config, :etcd_nodes)
    dir = Keyword.fetch!(config, :directory)
    ttl = Keyword.get(config, :ttl, @default_ttl)
    http_opts = Keyword.get(state.config, :http_opts, [])

    {:ok, :refreshed} = EtcdClient.refresh_ttl(etcd_nodes, dir, key, ttl, true, http_opts)
    send_refresh_ttl(config)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    etcd_nodes = Keyword.fetch!(state.config, :etcd_nodes)
    dir = Keyword.fetch!(state.config, :directory)
    http_opts = Keyword.get(state.config, :http_opts, [])

    EtcdClient.delete(etcd_nodes, dir, state.meta.registered_key, http_opts)

    debug(state.topology, "terminating with reason: #{inspect(reason)}")
  end

  def register(etcd_nodes, dir, ttl, http_opts) do
    EtcdClient.push(etcd_nodes, dir, Node.self() |> to_string(), ttl, http_opts)
  end

  def list_nodes(etcd_nodes, dir, http_opts) do
    with {:ok, key_value_pairs} <- EtcdClient.list(etcd_nodes, dir, http_opts) do
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

  defp send_check_nodes(config) do
    polling_interval = Keyword.get(config, :polling_interval, @default_polling_interval)
    Process.send_after(self(), :check_nodes, polling_interval)
  end

  defp send_refresh_ttl(config) do
    ttl_interval = Keyword.get(config, :ttl_refresh_interval, @default_ttl_refresh_interval)
    Process.send_after(self(), :refresh_ttl, ttl_interval)
  end

  defp etcd_server_url(address, port \\ @etcd_default_port) when is_binary(address) and is_integer(port) do
    address
    |> cleanup_trailing_slash()
    |> URI.parse()
    |> uri_check_scheme()
    |> uri_check_host()
    |> uri_set_port(port)
    |> URI.to_string()
  end

  defp cleanup_trailing_slash(address) do
    if String.ends_with?(address, "/") do
      address |> String.slice(0..-2)
    else
      address
    end
  end

  defp uri_check_scheme(%URI{scheme: nil} = uri), do: %URI{uri | scheme: "http"}
  defp uri_check_scheme(%URI{scheme: _scheme} = uri), do: uri

  defp uri_check_host(%URI{host: nil} = uri), do: %URI{uri | host: uri.path, path: nil}
  defp uri_check_host(%URI{host: _host} = uri), do: uri

  defp uri_set_port(%URI{} = uri, port) when is_integer(port), do: %URI{uri | port: port}
end
