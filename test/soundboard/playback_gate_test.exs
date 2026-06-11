defmodule Soundboard.PlaybackGateTest do
  use ExUnit.Case, async: true

  alias Soundboard.PlaybackGate

  # The gate is started by the application supervision tree, so the ETS table
  # already exists. Each test uses a unique clip name to stay isolated.
  defp unique_name, do: "gate-test-#{System.unique_integer([:positive])}.mp3"

  test "allows the first request for a clip" do
    assert PlaybackGate.request(unique_name()) == :ok
  end

  test "debounces a rapid second request for the same clip" do
    name = unique_name()
    assert PlaybackGate.request(name) == :ok
    assert PlaybackGate.request(name) == {:error, :debounced}
  end

  test "allows the request again after the debounce window elapses" do
    name = unique_name()
    assert PlaybackGate.request(name) == :ok
    assert PlaybackGate.request(name) == {:error, :debounced}

    # Window is 750ms; wait past it.
    Process.sleep(800)
    assert PlaybackGate.request(name) == :ok
  end

  test "treats distinct clips independently" do
    assert PlaybackGate.request(unique_name()) == :ok
    assert PlaybackGate.request(unique_name()) == :ok
  end

  test "fails open for non-binary input" do
    assert PlaybackGate.request(nil) == :ok
  end
end
