defmodule Soundboard.Sound do
  @moduledoc """
  Sound schema.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @type t :: %__MODULE__{}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  @spec with_tags(Ecto.Queryable.t()) :: Ecto.Query.t()
  @spec by_tag(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()

  schema "sounds" do
    field :filename, :string
    field :url, :string
    field :source_type, :string, default: "local"
    field :description, :string
    field :volume, :float, default: 1.0
    field :duration_ms, :integer
    field :internal_cooldown_seconds, :integer, default: 0
    belongs_to :user, Soundboard.Accounts.User

    many_to_many :tags, Soundboard.Tag,
      join_through: Soundboard.SoundTag,
      on_replace: :delete,
      unique: true

    timestamps()
  end

  def changeset(sound, attrs) do
    sound
    |> cast(attrs, [
      :filename,
      :url,
      :source_type,
      :description,
      :user_id,
      :volume,
      :duration_ms,
      :internal_cooldown_seconds
    ])
    |> validate_required([:user_id])
    |> validate_source_type()
    |> validate_volume()
    |> validate_duration()
    |> validate_internal_cooldown()
    |> unique_constraint(:filename, name: :sounds_filename_index)
    |> put_tags(attrs)
  end

  def with_tags(query \\ __MODULE__) do
    from s in query,
      preload: [:tags]
  end

  def by_tag(query \\ __MODULE__, tag_name) do
    from s in query,
      join: t in assoc(s, :tags),
      where: t.name == ^tag_name
  end

  defp validate_source_type(changeset) do
    case get_field(changeset, :source_type) do
      "local" -> validate_required(changeset, [:filename])
      "url" -> validate_required(changeset, [:url])
      _ -> add_error(changeset, :source_type, "must be either 'local' or 'url'")
    end
  end

  defp put_tags(changeset, %{tags: tags}) when is_list(tags) do
    put_assoc(changeset, :tags, tags)
  end

  defp put_tags(changeset, _), do: changeset

  defp validate_volume(changeset) do
    changeset
    |> validate_number(:volume,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.5
    )
    |> case do
      %{changes: %{volume: volume}} = cs when is_nil(volume) ->
        put_change(cs, :volume, 1.0)

      cs ->
        cs
    end
  end

  defp validate_internal_cooldown(changeset) do
    changeset
    |> validate_number(:internal_cooldown_seconds, greater_than_or_equal_to: 0)
    |> case do
      %{changes: %{internal_cooldown_seconds: cooldown}} = cs when is_nil(cooldown) ->
        put_change(cs, :internal_cooldown_seconds, 0)

      cs ->
        cs
    end
  end

  defp validate_duration(changeset) do
    validate_number(changeset, :duration_ms, greater_than_or_equal_to: 0)
  end
end
