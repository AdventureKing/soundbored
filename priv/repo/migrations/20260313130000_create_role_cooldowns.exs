defmodule Soundboard.Repo.Migrations.CreateRoleCooldowns do
  use Ecto.Migration

  def up do
    unless table_exists?("role_cooldowns") do
      create table(:role_cooldowns) do
        add(:role_id, :string, null: false)
        add(:cooldown_seconds, :integer, null: false)

        timestamps()
      end

      create(unique_index(:role_cooldowns, [:role_id]))
      # SQLite does not support ALTER TABLE ADD CONSTRAINT in Ecto migrations.
      # Positive cooldown validation is enforced by the RoleCooldown changeset.
    end
  end

  def down do
    drop_if_exists(table(:role_cooldowns))
  end

  defp table_exists?(table_name) do
    result =
      repo().query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table_name]
      )

    result.num_rows > 0
  end
end
