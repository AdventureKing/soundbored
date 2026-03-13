defmodule Soundboard.Repo.Migrations.AddDiscordRolesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :discord_roles, {:array, :string}, default: [], null: false
    end
  end
end
