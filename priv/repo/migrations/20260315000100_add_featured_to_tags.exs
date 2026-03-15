defmodule Soundboard.Repo.Migrations.AddFeaturedToTags do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :featured, :boolean, null: false, default: false
    end

    create index(:tags, [:featured])
  end
end
