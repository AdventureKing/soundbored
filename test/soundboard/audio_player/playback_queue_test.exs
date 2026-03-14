defmodule Soundboard.AudioPlayer.PlaybackQueueTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.AudioPlayer.PlaybackQueue
  alias Soundboard.AudioPlayer.State

  defp base_state(overrides \\ []) do
    struct!(
      State,
      Keyword.merge(
        [
          voice_channel: {"guild-1", "channel-9"},
          current_playback: nil,
          pending_requests: []
        ],
        overrides
      )
    )
  end

  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        guild_id: "guild-1",
        channel_id: "channel-9",
        sound_name: "intro.mp3",
        path_or_url: "/tmp/intro.mp3",
        volume: 0.8,
        actor: "System"
      },
      overrides
    )
  end

  test "build_request returns a normalized playback request" do
    with_mocks([
      {Soundboard.ClipCooldown, [], [check: fn "intro.mp3" -> :ok end]},
      {Soundboard.AudioPlayer.SoundLibrary, [],
       [get_sound_path: fn "intro.mp3" -> {:ok, {"/tmp/intro.mp3", 0.8}} end]}
    ]) do
      assert {:ok,
              %{
                guild_id: "guild-1",
                channel_id: "channel-9",
                sound_name: "intro.mp3",
                path_or_url: "/tmp/intro.mp3",
                volume: 0.8,
                actor: "System"
              }} = PlaybackQueue.build_request({"guild-1", "channel-9"}, "intro.mp3", "System")
    end
  end

  test "build_request returns lookup errors unchanged" do
    with_mocks([
      {Soundboard.ClipCooldown, [], [check: fn "missing.mp3" -> :ok end]},
      {Soundboard.AudioPlayer.SoundLibrary, [],
       [get_sound_path: fn "missing.mp3" -> {:error, "Sound not found"} end]}
    ]) do
      assert {:error, "Sound not found"} =
               PlaybackQueue.build_request({"guild-1", "channel-9"}, "missing.mp3", "System")
    end
  end

  test "build_request returns clip cooldown errors as user-friendly messages" do
    with_mock Soundboard.ClipCooldown,
      check: fn "intro.mp3" ->
        {:error,
         %{cooldown_seconds: 10, remaining_seconds: 5, last_played_at: NaiveDateTime.utc_now()}}
      end,
      message: fn _details -> "That clip is on cooldown. Try again in 5s." end do
      assert {:error, message} =
               PlaybackQueue.build_request({"guild-1", "channel-9"}, "intro.mp3", "System")

      assert message =~ "That clip is on cooldown"
    end
  end

  test "enqueue starts playback immediately when idle" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "intro.mp3", "/tmp/intro.mp3", 0.8, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state = PlaybackQueue.enqueue(base_state(), request())

      assert %{sound_name: "intro.mp3", task_ref: ref, task_pid: pid} = state.current_playback
      assert is_reference(ref)
      assert is_pid(pid)
      assert state.pending_requests == []

      assert_receive :play_started

      PlaybackQueue.clear_all(state)
    end
  end

  test "enqueue queues requests when playback is already active" do
    current = %{guild_id: "guild-1", sound_name: "old.mp3"}
    next = request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})

    with_mock Soundboard.Discord.Voice, stop: fn _guild_id -> :ok end do
      state = PlaybackQueue.enqueue(base_state(current_playback: current), next)

      assert state.current_playback == current
      assert state.pending_requests == [next]
      assert_not_called(Soundboard.Discord.Voice.stop(:_))
    end
  end

  test "clear_all resets playback and queued requests" do
    state =
      base_state(
        current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
        pending_requests: [
          request(%{sound_name: "next.mp3"}),
          request(%{sound_name: "later.mp3"})
        ]
      )
      |> PlaybackQueue.clear_all()

    assert state.current_playback == nil
    assert state.pending_requests == []
  end

  test "handle_task_result marks successful playback task as completed" do
    current = %{
      guild_id: "guild-1",
      sound_name: "intro.mp3",
      task_pid: self(),
      task_ref: make_ref()
    }

    state =
      base_state(current_playback: current)
      |> PlaybackQueue.handle_task_result(:ok)

    assert %{sound_name: "intro.mp3", task_pid: nil, task_ref: nil} = state.current_playback
  end

  test "handle_task_result clears failed playback and starts the next queued request" do
    test_pid = self()
    current = %{guild_id: "guild-1", sound_name: "old.mp3"}

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: current,
          pending_requests: [
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
          ]
        )
        |> PlaybackQueue.handle_task_result(:error)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_requests == []

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_task_result drops incompatible queued requests and starts the next compatible one" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_requests: [
            request(%{
              guild_id: "other-guild",
              channel_id: "other-channel",
              sound_name: "stale.mp3"
            }),
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
          ]
        )
        |> PlaybackQueue.handle_task_result(:error)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_requests == []

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_task_down clears crashed playback and starts the next queued request" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_requests: [
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
          ]
        )
        |> PlaybackQueue.handle_task_down(:boom)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_requests == []

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_playback_finished clears matching playback and starts the next queued request" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_requests: [
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
          ]
        )
        |> PlaybackQueue.handle_playback_finished("guild-1")

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_requests == []

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_playback_finished ignores unrelated guilds" do
    state =
      base_state(current_playback: %{guild_id: "guild-1", sound_name: "intro.mp3"})
      |> PlaybackQueue.handle_playback_finished("other-guild")

    assert state.current_playback.sound_name == "intro.mp3"
  end
end
