defmodule Statix.Conn do
  @moduledoc false

  defstruct [:sock, :address, :port, :prefix, :is_ipv6]

  alias Statix.Packet

  require Logger

  def new(host, port, prefix) when is_binary(host) do
    new(String.to_charlist(host), port, prefix)
  end

  def new(host, port, prefix) when is_list(host) or is_tuple(host) do
    case :inet.getaddr(host, :inet) do
      {:ok, address} ->
        %__MODULE__{address: address, port: port, prefix: prefix, is_ipv6: false}

      _ ->
        case :inet.getaddr(host, :inet6) do
          {:ok, address} ->
            %__MODULE__{address: address, port: port, prefix: prefix, is_ipv6: true}

          {:error, reason} ->
            raise(
              "cannot get the IP address for the provided host " <>
                "due to reason: #{:inet.format_error(reason)}"
            )
        end
    end
  end

  def open(%__MODULE__{is_ipv6: is_ipv6} = conn) do
    {:ok, sock} =
      case is_ipv6 do
        true -> :gen_udp.open(0, [{:active, false}, :inet6])
        false -> :gen_udp.open(0, [{:active, false}])
      end

    %__MODULE__{conn | sock: sock}
  end

  def transmit(%__MODULE__{sock: sock, prefix: prefix} = conn, type, key, val, options)
      when is_binary(val) and is_list(options) do
    result =
      prefix
      |> Packet.build(type, key, val, options)
      |> transmit(conn)

    with {:error, error} <- result do
      Logger.error(fn ->
        if(is_atom(sock), do: "", else: "Statix ") <>
          "#{inspect(sock)} #{type} metric \"#{key}\" lost value #{val}" <>
          " error=#{inspect(error)}"
      end)
    end

    result
  end

  defp transmit(packet, %__MODULE__{address: address, port: port, sock: sock_name}) do
    sock = Process.whereis(sock_name)

    if sock do
      :gen_udp.send(sock, address, port, packet)
    else
      {:error, :port_closed}
    end
  end
end
