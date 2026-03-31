defmodule Soundboard.Repo.Migrations.CreateCommercialClips do
  use Ecto.Migration

  def up do
    create table(:commercial_clips) do
      add :name, :string, null: false
      add :filename, :string, null: false

      timestamps()
    end

    create unique_index(:commercial_clips, [:filename])
  end

  def down do
    drop table(:commercial_clips)
  end
end
