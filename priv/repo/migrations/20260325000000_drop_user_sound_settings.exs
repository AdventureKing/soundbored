defmodule Soundboard.Repo.Migrations.DropUserSoundSettings do
  use Ecto.Migration

  def up do
    drop table(:user_sound_settings)
  end

  def down do
    create table(:user_sound_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sound_id, references(:sounds, on_delete: :delete_all), null: false
      add :is_join_sound, :boolean, default: false, null: false
      add :is_leave_sound, :boolean, default: false, null: false

      timestamps()
    end

    create index(:user_sound_settings, [:user_id])
    create index(:user_sound_settings, [:sound_id])
  end
end
