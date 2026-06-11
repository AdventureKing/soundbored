defmodule Soundboard.Commercials.Clip do
  @moduledoc """
  Stores a single commercial audio clip.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          filename: String.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "commercial_clips" do
    field :name, :string
    field :filename, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(clip, attrs) do
    clip
    |> cast(attrs, [:name, :filename])
    |> validate_required([:name, :filename])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:filename)
  end
end
