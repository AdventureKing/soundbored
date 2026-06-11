defmodule Soundboard.Commercials.Settings do
  @moduledoc """
  Stores global commercial playback configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          enabled: boolean(),
          inactivity_seconds: pos_integer(),
          interval_seconds: pos_integer(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "commercial_settings" do
    field :enabled, :boolean, default: false
    field :inactivity_seconds, :integer, default: 360
    field :interval_seconds, :integer, default: 360

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :inactivity_seconds, :interval_seconds])
    |> validate_required([:enabled, :inactivity_seconds, :interval_seconds])
    |> validate_number(:inactivity_seconds, greater_than: 0)
    |> validate_number(:interval_seconds, greater_than: 0)
  end
end
