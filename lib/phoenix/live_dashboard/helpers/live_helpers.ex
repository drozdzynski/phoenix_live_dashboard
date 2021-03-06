defmodule Phoenix.LiveDashboard.LiveHelpers do
  @moduledoc false

  import Phoenix.LiveView.Helpers

  @format_limit 100

  @doc """
  Computes a route path to the live dashboard.
  """
  def live_dashboard_path(socket, page, node, params \\ []) do
    apply(
      socket.router.__helpers__(),
      :live_dashboard_path,
      [socket, :page, node, page, params]
    )
  end

  @doc """
  Encodes Sockets for URLs.
  """
  def encode_socket(ref) do
    [_hash, _P, _o, _r, _t | port] = :erlang.port_to_list(ref)
    "Socket#{port}"
  end

  @doc """
  Encodes ETSs for URLs.
  """
  def encode_ets(ref) do
    [_hash, _R, _e, _f | ref] = :erlang.ref_to_list(ref)
    "ETS#{ref}"
  end

  @doc """
  Encodes PIDs for URLs.
  """
  def encode_pid(pid) do
    "PID#{:erlang.pid_to_list(pid)}"
  end

  @doc """
  Encodes Port for URLs.
  """
  def encode_port(port) when is_port(port) do
    port
    |> :erlang.port_to_list()
    |> tl()
    |> List.to_string()
  end

  @doc """
  Formats any value.
  """
  def format_value(port, live_dashboard_path) when is_port(port) do
    live_patch(inspect(port), to: live_dashboard_path.(node(port), info: encode_port(port)))
  end

  def format_value(pid, live_dashboard_path) when is_pid(pid) do
    live_patch(inspect(pid), to: live_dashboard_path.(node(pid), info: encode_pid(pid)))
  end

  def format_value([_ | _] = list, live_dashboard_path) do
    {entries, left_over} = Enum.split(list, @format_limit)

    entries
    |> Enum.map(&format_value(&1, live_dashboard_path))
    |> Kernel.++(if left_over == [], do: [], else: ["..."])
    |> Enum.intersperse({:safe, "<br />"})
  end

  def format_value(other, _socket), do: inspect(other, pretty: true, limit: @format_limit)

  @doc """
  Formats MFAs.
  """
  def format_call({m, f, a}), do: Exception.format_mfa(m, f, a)

  @doc """
  Formats the stacktrace.
  """
  def format_stacktrace(stacktrace) do
    stacktrace
    |> Exception.format_stacktrace()
    |> String.split("\n")
    |> Enum.map(&String.replace_prefix(&1, "    ", ""))
    |> Enum.join("\n")
  end

  @format_path_regex ~r/^(?<beginning>((.+?\/){3})).*(?<ending>(\/.*){3})$/

  @doc """
  Formats large paths by removing intermediate parts.
  """
  def format_path(path) do
    path_string =
      path
      |> to_string()
      |> String.replace_prefix("\"", "")
      |> String.replace_suffix("\"", "")

    case Regex.named_captures(@format_path_regex, path_string) do
      %{"beginning" => beginning, "ending" => ending} -> "#{beginning}...#{ending}"
      _ -> path_string
    end
  end

  @doc """
  Formats uptime.
  """
  def format_uptime(uptime) do
    {d, {h, m, _s}} = :calendar.seconds_to_daystime(div(uptime, 1000))

    cond do
      d > 0 -> "#{d}d#{h}h#{m}m"
      h > 0 -> "#{h}h#{m}m"
      true -> "#{m}m"
    end
  end

  @doc """
  Formats percent.
  """
  def format_percent(percent) when is_float(percent), do: "#{Float.round(percent, 1)}%"
  def format_percent(nil), do: "0%"
  def format_percent(percent), do: "#{percent}%"

  @doc """
  Formats words as bytes.
  """
  def format_words(words) when is_integer(words) do
    format_bytes(words * :erlang.system_info(:wordsize))
  end

  @doc """
  Formats bytes.
  """
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= memory_unit(:TB) -> format_bytes(bytes, :TB)
      bytes >= memory_unit(:GB) -> format_bytes(bytes, :GB)
      bytes >= memory_unit(:MB) -> format_bytes(bytes, :MB)
      bytes >= memory_unit(:KB) -> format_bytes(bytes, :KB)
      true -> format_bytes(bytes, :B)
    end
  end

  defp format_bytes(bytes, :B) when is_integer(bytes), do: "#{bytes} B"

  defp format_bytes(bytes, unit) when is_integer(bytes) do
    value = bytes / memory_unit(unit)
    "#{:erlang.float_to_binary(value, decimals: 1)} #{unit}"
  end

  defp memory_unit(:TB), do: 1024 * 1024 * 1024 * 1024
  defp memory_unit(:GB), do: 1024 * 1024 * 1024
  defp memory_unit(:MB), do: 1024 * 1024
  defp memory_unit(:KB), do: 1024

  @doc """
  Computes the percentage between `value` and `total`.
  """
  def percentage(value, total, rounds \\ 1)
  def percentage(_value, 0, _rounds), do: 0
  def percentage(nil, _total, _rounds), do: 0
  def percentage(value, total, rounds), do: Float.round(value / total * 100, rounds)

  @doc """
  Shows a hint.
  """
  def hint(do: block) do
    assigns = %{block: block}

    ~L"""
    <div class="hint">
      <svg class="hint-icon" viewBox="0 0 44 44" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect width="44" height="44" fill="none"/>
        <rect x="19" y="10" width="6" height="5.76" rx="1" class="hint-icon-fill"/>
        <rect x="19" y="20" width="6" height="14" rx="1" class="hint-icon-fill"/>
        <circle cx="22" cy="22" r="20" class="hint-icon-stroke" stroke-width="4"/>
      </svg>
      <div class="hint-text"><%= @block %></div>
    </div>
    """
  end

  @doc """
  Builds a modal.
  """
  def live_modal(socket, component, opts) do
    path = Keyword.fetch!(opts, :return_to)
    title = Keyword.fetch!(opts, :title)
    modal_opts = [id: :modal, return_to: path, component: component, opts: opts, title: title]
    live_component(socket, Phoenix.LiveDashboard.ModalComponent, modal_opts)
  end

  @doc """
  Builds a detail model based on detail parameters.
  """
  def live_info(_socket, %{info: nil}), do: nil

  def live_info(socket, %{info: {title, params}, node: node, page: page}) do
    if component = extract_info_component(title) do
      path = &live_dashboard_path(socket, page, &1, Enum.into(&2, params))

      live_modal(socket, component,
        id: title,
        return_to: path.(node, []),
        title: title,
        path: path,
        node: node
      )
    end
  end

  defp extract_info_component("PID<" <> _), do: Phoenix.LiveDashboard.ProcessInfoComponent
  defp extract_info_component("Port<" <> _), do: Phoenix.LiveDashboard.PortInfoComponent
  defp extract_info_component("Socket<" <> _), do: Phoenix.LiveDashboard.SocketInfoComponent
  defp extract_info_component("ETS<" <> _), do: Phoenix.LiveDashboard.EtsInfoComponent
  defp extract_info_component(_), do: nil

  @doc """
  All connected nodes (including the current node).
  """
  def nodes(), do: [node()] ++ Node.list(:connected)

  @doc """
  Callback that must be invoked on all mounts.
  """
  def assign_mount(socket, page, params, session, refresher? \\ false) do
    param_node = Map.fetch!(params, "node")
    found_node = Enum.find(nodes(), &(Atom.to_string(&1) == param_node))
    target_node = found_node || node()

    capabilities = Phoenix.LiveDashboard.SystemInfo.ensure_loaded(target_node)

    socket =
      Phoenix.LiveView.assign(socket, :menu, %{
        refresher?: refresher?,
        page: page,
        info: info(params),
        node: target_node,
        metrics: capabilities.dashboard && session["metrics"],
        os_mon: capabilities.os_mon,
        request_logger: capabilities.dashboard && session["request_logger"],
        dashboard_running?: capabilities.dashboard
      })

    if found_node do
      socket
    else
      Phoenix.LiveView.push_redirect(socket, to: live_dashboard_path(socket, :home, node()))
    end
  end

  defp info(%{"info" => info} = params), do: {info, Map.delete(params, "info")}
  defp info(%{}), do: nil

  @doc """
  Callback that must be invoked on all handle_params.
  """
  def assign_params(socket, params) do
    menu = socket.assigns.menu
    info = info(params)

    if menu.info != info do
      Phoenix.LiveView.assign(socket, :menu, %{menu | info: info})
    else
      socket
    end
  end
end
