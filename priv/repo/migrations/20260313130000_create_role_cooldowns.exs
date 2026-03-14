defmodule Soundboard.Repo.Migrations.CreateRoleCooldowns do
  use Ecto.Migration

  def change do
    create table(:role_cooldowns) do
      add(:role_id, :string, null: false)
      add(:cooldown_seconds, :integer, null: false)

      timestamps()
    end

    create(unique_index(:role_cooldowns, [:role_id]))

    create(
      constraint(
        :role_cooldowns,
        :cooldown_seconds_must_be_positive,
        check: "cooldown_seconds > 0"
      )
    )
  end
end
