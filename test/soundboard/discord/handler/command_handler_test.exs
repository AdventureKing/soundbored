defmodule Soundboard.Discord.Handler.CommandHandlerTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.Discord.Handler.CommandHandler
  alias Soundboard.Discord.Handler.VoiceRuntime
  alias Soundboard.Discord.Message

  setup do
    original_scheme = System.get_env("SCHEME")
    System.delete_env("SCHEME")

    on_exit(fn ->
      case original_scheme do
        nil -> System.delete_env("SCHEME")
        value -> System.put_env("SCHEME", value)
      end
    end)

    :ok
  end

  test "!join uses the endpoint URL when building the response message" do
    with_mocks([
      {VoiceRuntime, [],
       [
         user_voice_channel: fn "guild-1", "user-1" -> "voice-1" end,
         join_voice_channel: fn "guild-1", "voice-1" -> :ok end
       ]},
      {Message, [],
       [
         create: fn channel_id, body ->
           send(self(), {:created_message, channel_id, body})
           :ok
         end
       ]}
    ]) do
      CommandHandler.handle_message(%{
        content: "!join",
        guild_id: "guild-1",
        channel_id: "text-1",
        author: %{id: "user-1"}
      })

      assert_receive {:created_message, "text-1", payload}
      assert payload.content =~ "Joined your voice channel!"
      assert payload.content =~ SoundboardWeb.Endpoint.url()
      refute payload.content =~ "nil://"
      assert payload.flags == 4
    end
  end

  test "!leave leaves the current voice channel and confirms in chat" do
    with_mocks([
      {VoiceRuntime, [], [leave_voice_channel: fn "guild-1" -> :ok end]},
      {Message, [],
       [
         create: fn channel_id, body ->
           send(self(), {:created_message, channel_id, body})
           :ok
         end
       ]}
    ]) do
      assert :ok =
               CommandHandler.handle_message(%{
                 content: "!leave",
                 guild_id: "guild-1",
                 channel_id: "text-1"
               })

      assert_receive {:created_message, "text-1", "Left the voice channel!"}
    end
  end
end
