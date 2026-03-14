defmodule Soundboard.Accounts.RoleCooldown do
  @moduledoc """
  Stores playback cooldown settings per Discord role ID.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          role_id: String.t() | nil,
          cooldown_seconds: pos_integer() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "role_cooldowns" do
    field(:role_id, :string)
    field(:cooldown_seconds, :integer)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(role_cooldown, attrs) do
    role_cooldown
    |> cast(attrs, [:role_id, :cooldown_seconds])
    |> validate_required([:role_id, :cooldown_seconds])
    |> validate_number(:cooldown_seconds, greater_than: 0)
    |> validate_length(:role_id, min: 1)
    |> unique_constraint(:role_id)
  end
end
