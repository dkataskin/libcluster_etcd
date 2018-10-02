defmodule LibclusterEtcd.EtcdClient do
  @keys "/v2/keys"
  @httpc_opts [body_format: :binary, full_result: false]
  @default_http_opts [
    timeout: 10_000,
    connect_timeout: 2_000,
    autoredirect: false,
    relaxed: true
  ]
  @default_ttl 30_000

  def push(seeds, dir, value, ttl \\ @default_ttl, http_opts \\ [])
      when is_binary(dir) and is_integer(ttl) do
    request = {:post, dir, %{"value" => value, "ttl" => round(ttl / 1000)}}
    with {:ok, {201, response}} <- exec_request(seeds, request, http_opts),
         {:ok, json} <- Jason.decode(response),
         key <- json |> Map.fetch!("node") |> Map.fetch!("key") |> cleanup(dir) do
      {:ok, :binary.copy(key)}
    else
      {:error, error} ->
        {:error, error}

      error ->
        {:error, error}
    end
  end

  def refresh_ttl(seeds, dir, key, ttl \\ @default_ttl, prev_exist \\ true, http_opts \\ [])
      when is_binary(dir) and is_binary(key) and is_integer(ttl) do
    payload = %{
      "ttl" => round(ttl / 1000),
      "refresh" => true,
      "prevExist" => prev_exist
    }

    with {:ok, {200, _response}} <- exec_request(seeds, {:put, dir <> "/" <> key, payload}, http_opts) do
      {:ok, :refreshed}
    else
      {:error, error} ->
        {:error, error}

      {:ok, {404, _}} ->
        {:error, :key_not_found}

      error ->
        {:error, error}
    end
  end

  def list(seeds, dir, http_opts \\ []) when is_binary(dir) do
    with {:ok, {200, response}} <- exec_request(seeds, {:get, dir}, http_opts),
         {:ok, json} <- Jason.decode(response) do
      keys =
        json
        |> Map.get("node", %{"nodes" => []})
        |> Map.get("nodes", [])
        |> Enum.map(fn map ->
          key = map |> Map.fetch!("key") |> cleanup(dir)
          {:binary.copy(key), :binary.copy(map["value"])}
        end)

      {:ok, keys}
    else
      {:error, error} ->
        {:error, error}

      {:ok, {404, _}} ->
        {:ok, []}

      error ->
        {:error, error}
    end
  end

  def delete(seeds, dir, key, http_opts \\ []) when is_binary(dir) and is_binary(key) do
    with {:ok, {200, _response}} <- exec_request(seeds, {:delete, dir <> "/" <> "key"}, http_opts) do
      {:ok, :deleted}
    else
      {:error, error} ->
        {:error, error}

      error ->
        {:error, error}
    end
  end

  defp exec_request(seeds, request, http_opts) do
    req_http_opts = @default_http_opts |> Keyword.merge(http_opts)
    
    seeds
    |> Enum.shuffle()
    |> do_exec_request(request, req_http_opts, nil)
  end

  defp do_exec_request([], _req, _http_opts, error), do: {:error, error}
  defp do_exec_request([seed | seeds], {method, path} = req, http_opts, _error) do
    request = make_request(seed, path)
    with {:ok, result} <- :httpc.request(method, request, http_opts, @httpc_opts) do
      {:ok, result}
    else
      error ->
        do_exec_request(seeds, req, http_opts, error)
    end
  end

  defp do_exec_request([seed | seeds], {method, path, payload} = req, http_opts, _error) do
    request = make_request(seed, path, payload)
    with {:ok, result} <- :httpc.request(method, request, http_opts, @httpc_opts) do
      {:ok, result}
    else
      error ->
        do_exec_request(seeds, req, http_opts, error)
    end
  end

  defp make_request(etcd_server, path) do
    url = etcd_server |> make_url(path) |> String.to_charlist()

    {url, []}
  end

  defp make_request(etcd_server, path, payload) do
    url = etcd_server |> make_url(path) |> String.to_charlist()

    {url, [], 'application/x-www-form-urlencoded', payload |> form_encode()}
  end

  defp make_url(base, path) do
    if String.starts_with?(path, "/") do
      base <> @keys <> path
    else
      base <> @keys <> "/" <> path
    end
  end

  defp form_encode(payload) when is_map(payload),
    do: payload |> Enum.map_join("&", fn {key, value} -> "#{key}=#{value}" end)

  defp cleanup(key, dir) when is_binary(dir) and is_binary(key) do
    key
    |> String.slice((String.length(dir) + 2)..(String.length(key) - 1))
  end
end
