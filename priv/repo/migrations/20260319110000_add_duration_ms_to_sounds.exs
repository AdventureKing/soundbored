defmodule Soundboard.Repo.Migrations.AddDurationMsToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :duration_ms, :integer
    end
  end
end
