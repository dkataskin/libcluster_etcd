defmodule LibclusterEtcd.EtcdClient do
  @keys "/v2/keys"
  @default_http_opts [timeout: 20_000, connect_timeout: 20_000, autoredirect: false, relaxed: true]
  @default_ttl 30

  def push(etcd_server, dir, value, ttl \\ @default_ttl, http_opts \\ [])
  when is_binary(dir) and is_integer(ttl) do
    req = make_request(etcd_server, dir, %{"value" => value, "ttl" => ttl})
    with {:ok, {201, response}} <- exec_request(:post, req, http_opts),
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

  def refresh_ttl(etcd_server, dir, key, ttl \\ @default_ttl, prev_exist \\ true, http_opts \\ [])
  when is_binary(dir) and is_binary(key) and is_integer(ttl) do
    req = make_request(etcd_server, dir <> "/" <> key, %{"ttl" => ttl, "refresh" => true, "prevExist" => prev_exist})
    with {:ok, {200, _response}} <- exec_request(:put, req, http_opts) do
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

  def list(etcd_server, dir, http_opts \\ []) when is_binary(dir) do
    req = make_request(etcd_server, dir)
    with {:ok, {200, response}} <- exec_request(:get, req, http_opts),
         {:ok, json} <- Jason.decode(response) do
      keys = json
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

  def delete(etcd_server, dir, key, http_opts \\ []) when is_binary(dir) and is_binary(key) do
    req = make_request(etcd_server, dir <> "/" <> "key")
    with {:ok, {200, _response}} <- exec_request(:delete, req, http_opts) do
      {:ok, :deleted}
    else
      {:error, error} ->
        {:error, error}

      error ->
        {:error, error}
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

  defp exec_request(method, request, http_opts) do
    req_http_opts = @default_http_opts |> Keyword.merge(http_opts)
    opts = [body_format: :binary, full_result: false]

    with {:ok, result} <- :httpc.request(method, request, req_http_opts, opts) do
      {:ok, result}
    end
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
    |> String.slice(String.length(dir) + 2..String.length(key) - 1)
  end
end