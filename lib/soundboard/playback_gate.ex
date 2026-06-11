defmodule Soundboard.PlaybackGate do
  @moduledoc """
  Sub-second debounce gate that prevents the same clip from being
  re-triggered in rapid succession (e.g. from spam-clicking the UI).

  Backed by a public ETS table keyed by clip name. This is intentionally
  separate from the user-facing cooldowns in `Soundboard.ClipCooldown` and
  `Soundboard.PlaybackCooldown`, which are opt-in and read the database at
  second granularity. Those checks can't catch a burst of clicks that all
  arrive before any `Play` row is written; this gate can.
  """

  use GenServer

  @table __MODULE__
  @window_ms 750
  @sweep_interval_ms 60_000

  # Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `:ok` if the clip may play, or `{:error, :debounced}` if the same
  clip was requested within the debounce window (#{@window_ms}ms).
  """
  @spec request(String.t()) :: :ok | {:error, :debounced}
  def request(sound_name) when is_binary(sound_name) do
    now = System.monotonic_time(:millisecond)

    # insert_new wins the race on a cold key; the loser falls through to the
    # window check below.
    if :ets.insert_new(@table, {sound_name, now}) do
      :ok
    else
      case :ets.lookup(@table, sound_name) do
        [{^sound_name, last}] when now - last < @window_ms ->
          {:error, :debounced}

        _ ->
          :ets.insert(@table, {sound_name, now})
          :ok
      end
    end
  rescue
    ArgumentError ->
      # Table not available (e.g. during shutdown); fail open so playback works.
      :ok
  end

  def request(_), do: :ok

  # Server

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end
