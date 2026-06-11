defmodule Soundboard.Repo.Migrations.CreateCommercialSettings do
  use Ecto.Migration

  def up do
    create table(:commercial_settings) do
      add :enabled, :boolean, default: false, null: false
      add :inactivity_seconds, :integer, default: 360, null: false
      add :interval_seconds, :integer, default: 360, null: false

      timestamps()
    end
  end

  def down do
    drop table(:commercial_settings)
  end
end
