defmodule Soundboard.Discord.HandlerTest do
  @moduledoc """
  Tests the DiscordHandler module.
  """
  use Soundboard.DataCase

  import ExUnit.CaptureLog
  import Mock

  alias Soundboard.Discord.Handler
  alias Soundboard.Discord.Voice

  setup do
    :persistent_term.put(:soundboard_bot_ready, true)

    on_exit(fn ->
      :persistent_term.erase(:soundboard_bot_ready)
    end)

    :ok
  end

  describe "handle_event/1" do
    test "handles voice state updates" do
      mock_guild = %{
        id: "456",
        voice_states: [
          %{
            user_id: "789",
            channel_id: "123",
            guild_id: "456",
            session_id: "abc"
          }
        ]
      }

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn _, _ -> :ok end,
             ready?: fn _ -> false end
           ]},
          {Soundboard.Discord.GuildCache, [], [get: fn _guild_id -> {:ok, mock_guild} end]},
          {Soundboard.Discord.BotIdentity, [], [fetch: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          Handler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert_called(Voice.join_channel("456", "123"))
        end
      end)
    end

    test "does not auto-join when guild cache is unavailable" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn guild_id, channel_id ->
               Agent.update(recorder, &(&1 ++ [{guild_id, channel_id}]))
               :ok
             end,
             ready?: fn _ -> false end
           ]},
          {Soundboard.Discord.GuildCache, [],
           [all: fn -> [] end, get: fn _guild_id -> :error end]},
          {Soundboard.Discord.BotIdentity, [], [fetch: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          Handler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          assert Agent.get(recorder, & &1) == []
        end
      end)
    end

    test "schedules runtime follow-up messages from the handler boundary" do
      payload = %{channel_id: "123", guild_id: "456", user_id: "999", session_id: "abc"}

      with_mocks([
        {Soundboard.Discord.Handler.VoiceRuntime, [],
         [
           bot_user?: fn _ -> true end,
           handle_connect: fn ^payload ->
             [{:schedule_recheck_alone, "456", "123", 0}]
           end
         ]}
      ]) do
        assert {:noreply, nil} =
                 Handler.handle_cast({:eda_event, {:VOICE_STATE_UPDATE, payload, nil}}, nil)

        assert_receive {:recheck_alone, "456", "123"}
      end
    end

    test "voice commands update the audio player once after the Discord call succeeds" do
      guild_id = "456"
      channel_id = "123"
      user_id = "777"

      guild = %{
        id: guild_id,
        voice_states: [
          %{user_id: user_id, channel_id: channel_id, guild_id: guild_id, session_id: "voice"}
        ]
      }

      {:ok, recorder} = Agent.start_link(fn -> [] end)

      capture_log(fn ->
        with_mocks([
          {Soundboard.Discord.GuildCache, [],
           [get!: fn ^guild_id -> guild end, get: fn ^guild_id -> {:ok, guild} end]},
          {Soundboard.Discord.BotIdentity, [], [fetch: fn -> {:ok, %{id: "999"}} end]},
          {Soundboard.Discord.Message, [], [create: fn _, _ -> :ok end]},
          {Soundboard.Discord.Voice, [],
           [
             join_channel: fn ^guild_id, ^channel_id ->
               Agent.update(recorder, &(&1 ++ [{:join_channel, guild_id, channel_id}]))
               :ok
             end,
             leave_channel: fn ^guild_id ->
               Agent.update(recorder, &(&1 ++ [{:leave_channel, guild_id}]))
               :ok
             end
           ]},
          {Soundboard.AudioPlayer, [],
           [
             set_voice_channel: fn guild, channel ->
               Agent.update(recorder, &(&1 ++ [{:set_voice_channel, guild, channel}]))
               :ok
             end
           ]}
        ]) do
          Handler.handle_event({
            :MESSAGE_CREATE,
            %{content: "!join", guild_id: guild_id, channel_id: "text", author: %{id: user_id}},
            nil
          })

          Handler.handle_event({
            :MESSAGE_CREATE,
            %{content: "!leave", guild_id: guild_id, channel_id: "text", author: %{id: user_id}},
            nil
          })

          assert Agent.get(recorder, & &1) == [
                   {:join_channel, guild_id, channel_id},
                   {:set_voice_channel, guild_id, channel_id},
                   {:leave_channel, guild_id},
                   {:set_voice_channel, nil, nil}
                 ]
        end
      end)
    end
  end

end
