defmodule Soundboard.Repo.Migrations.AddDiscordRolesToUsers do
  use Ecto.Migration

  def up do
    unless column_exists?("users", "discord_roles") do
      alter table(:users) do
        add(:discord_roles, {:array, :string}, default: [], null: false)
      end
    end
  end

  def down do
    # SQLite does not support dropping a single column without table rebuild.
    :ok
  end

  defp column_exists?(table_name, column_name) do
    result = repo().query!("PRAGMA table_info(#{table_name})")

    Enum.any?(result.rows, fn
      [_cid, ^column_name | _rest] -> true
      _row -> false
    end)
  end
end
