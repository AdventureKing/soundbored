defmodule Soundboard.Media.DurationTest do
  use ExUnit.Case, async: true

  alias Soundboard.Media.Duration

  describe "parse_duration_output/1" do
    test "parses a plain numeric value" do
      assert {:ok, 1_230} = Duration.parse_duration_output("1.23\n")
    end

    test "parses output with surrounding lines" do
      output = """
      warning line
      42.5
      trailing line
      """

      assert {:ok, 42_500} = Duration.parse_duration_output(output)
    end

    test "returns an error for non numeric output" do
      assert {:error, :invalid_duration} = Duration.parse_duration_output("not-a-number")
    end
  end
end
