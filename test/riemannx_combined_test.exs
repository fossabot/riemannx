defmodule RiemannxTest.Combined do
  use ExUnit.Case, async: false
  use PropCheck
  import Riemannx.Settings
  alias Riemannx.Proto.Msg
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :combined)
    Application.put_env(:riemannx, :max_udp_size, 16384)
    :ok
  end

  setup do
    {:ok, tcp_server} = RiemannxTest.Servers.TCP.start(self())
    {:ok, udp_server} = RiemannxTest.Servers.UDP.start(self())
    Application.ensure_all_started(:riemannx)
    Application.put_env(:riemannx, :max_udp_size, 16384)

    on_exit(fn() ->
      RiemannxTest.Servers.TCP.stop(tcp_server)
      RiemannxTest.Servers.UDP.stop(udp_server)
      Application.stop(:riemannx)
    end)

    [tcp_server: tcp_server, udp_server: udp_server]
  end

  test "send_async/1 can send an event" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    Riemannx.send_async(event)
    assert_events_received(event)
  end

  test "send_async/1 can send multiple events" do
    events = [
      [
        service: "riemann-elixir",
        metric: 1,
        attributes: [a: 1],
        description: "hurr durr"
      ],
      [
        service: "riemann-elixir-2",
        metric: 1.123,
        attributes: [a: 1, "b": 2],
        description: "hurr durr dee durr"
      ],
      [
        service: "riemann-elixir-3",
        metric: 5.123,
        description: "hurr durr dee durr derp"
      ],
      [
        service: "riemann-elixir-4",
        state: "ok"
      ]
    ]
    Riemannx.send_async(events)
    assert_events_received(events)
  end

  test "The message is still sent given a small max_udp_size" do
    events = [
      [
        service: "riemann-elixir",
        metric: 1,
        attributes: [a: 1],
        description: "hurr durr"
      ],
      [
        service: "riemann-elixir-2",
        metric: 1.123,
        attributes: [a: 1, "b": 2],
        description: "hurr durr dee durr"
      ],
      [
        service: "riemann-elixir-3",
        metric: 5.123,
        description: "hurr durr dee durr derp"
      ],
      [
        service: "riemann-elixir-4",
        state: "ok"
      ]
    ]
    Application.put_env(:riemannx, :max_udp_size, 1)
    Riemannx.send_async(events)
    assert_events_received(events, :tcp)
    Application.put_env(:riemannx, :max_udp_size, 16384)
  end


  property "All reasonable metrics async", [:verbose] do
    numtests(250, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  property "All reasonable metrics sync", [:verbose] do
    numtests(250, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        :ok = Riemannx.send(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  def assert_events_received(events) do
    orig    = Riemannx.create_events_msg(events)
    msg     = orig |> Msg.decode()
    events  = msg.events |> Enum.map(fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, x} ->
        if byte_size(orig) > max_udp_size() do
          assert x == :tcp
          true
        else
          assert x == :udp
          true
        end
    after 10_000 -> false
    end
  end
  def assert_events_received(events, x) do
    msg     = Riemannx.create_events_msg(events) |> Msg.decode()
    events  = msg.events |> Enum.map(fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, ^x} -> true
    after 10_000 -> false
    end
  end
end
