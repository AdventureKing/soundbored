defmodule SoundboardWeb.SoundHelpersTest do
  use ExUnit.Case, async: true
  alias SoundboardWeb.SoundHelpers

  describe "display_name/1" do
    test "strips extension and directories" do
      assert SoundHelpers.display_name("priv/static/uploads/beep.mp3") == "beep"
    end

    test "handles values without extension" do
      assert SoundHelpers.display_name("wow") == "wow"
    end

    test "handles nil" do
      assert SoundHelpers.display_name(nil) == ""
    end

    test "stringifies non-binary values" do
      assert SoundHelpers.display_name(123) == "123"
    end
  end

  describe "slugify/1" do
    test "converts filename to lower-case slug" do
      assert SoundHelpers.slugify("Wow Sound.MP3") == "wow-sound"
    end

    test "falls back to default" do
      assert SoundHelpers.slugify(nil) == "sound"
    end
  end

  describe "upload_path/1" do
    test "builds an uploads path with escaped filename characters" do
      assert SoundHelpers.upload_path("what?.mp3") == "/uploads/what%3F.mp3"
    end

    test "returns an empty string for nil" do
      assert SoundHelpers.upload_path(nil) == ""
    end
  end
end
