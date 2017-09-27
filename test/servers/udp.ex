defmodule RiemannxTest.Servers.UDP do
  use GenServer
  
  def start(test_pid) do
    {:ok, server} = GenServer.start(__MODULE__, %{test_pid: test_pid, socket: nil})
    :ok = GenServer.call(server, :open)
    {:ok, server}
  end
  
  def stop(server) do
    Process.exit(server, :shutdown)
  end
  
  def init(state) do
    {:ok, state}
  end
  
  def handle_call(:open, _from, state) do
    port = Application.get_env(:riemannx, :udp_port, 5555)
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:reply, :ok, %{state | socket: socket}}
  end
  
  def handle_info({:udp, _, _, _, msg}, state) do
    send(state.test_pid, {msg, :udp})
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
  end
end