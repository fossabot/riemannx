defmodule Riemannx.Connections.Batch do
  @moduledoc """
  The batch connector is a pass through module that adds batching functionality
  on top of the existing protocol connections.

  Batching will aggregate events you send and then send them in bulk in
  intervals you specify, if the events reach a certain size you can set it so
  they publish the events before the interval.

  NOTE: Batching **only** works with send_async.

  Below is how the batching settings look in config:

  ```elixir
    config :riemannx, [
      type: :batch
      batch_settings: [
        type: :combined
        size: 50 # Sends when the batch size reaches 50
        interval: {5, :seconds} # How often to send the batches if they don't reach :size (:seconds, :minutes or :milliseconds)
      ]
    ]

  ## Synchronous Sending

  When you send synchronously the events are passed directly through to the underlying connection
  module. They are not batched or put in the queue.
  ```
  """
  import Riemannx.Settings
  import Kernel, except: [send: 2]
  alias Riemannx.Proto.Msg
  use GenServer

  @behaviour Riemannx.Connection

  # ===========================================================================
  # API
  # ===========================================================================
  def send(e, t), do: batch_module().send(e, t)
  def send_async(e), do: GenServer.cast(__MODULE__, {:push, e})
  def query(m, t), do: batch_module().query(m, t)

  # ===========================================================================
  # GenStage Callbacks
  # ===========================================================================
  def start_link([]) do
    GenServer.start_link(__MODULE__, Qex.new(), name: __MODULE__)
  end

  def init(queue) do
    Process.send_after(self(), :flush, batch_interval())
    {:ok, queue}
  end

  def handle_cast({:push, event}, queue) do
    queue = Qex.push(queue, event)

    if Enum.count(queue) >= batch_size(),
      do: {:noreply, flush(queue)},
      else: {:noreply, queue}
  end

  def handle_info(:flush, queue), do: {:noreply, flush(queue)}
  def handle_info(_, queue), do: {:noreply, queue}

  # ===========================================================================
  # Private
  # ===========================================================================
  defp flush(items) when is_list(items) do
    batch =
      Enum.flat_map(items, fn item ->
        item
      end)

    [events: batch]
    |> Msg.new()
    |> Msg.encode()
    |> batch_module().send_async()

    Process.send_after(self(), :flush, batch_interval())
  end

  defp flush(queue) do
    queue |> Enum.to_list() |> flush()
    Qex.new()
  end
end
