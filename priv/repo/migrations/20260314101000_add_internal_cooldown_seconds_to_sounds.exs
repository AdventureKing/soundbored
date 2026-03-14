defmodule Soundboard.Repo.Migrations.AddInternalCooldownSecondsToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :internal_cooldown_seconds, :integer, default: 0, null: false
    end
  end
end
