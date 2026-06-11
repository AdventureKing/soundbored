Code.compiler_options(ignore_module_conflict: true)

System.put_env("MIX_ENV", "test")
Mix.start()

args = System.argv()

if args == [] do
  IO.puts(:stderr, "usage: elixir scripts/mix_test_workaround.exs path/to/test.exs[:line] ...")
  System.halt(1)
end

for ebin <- Path.wildcard("_build/test/lib/*/ebin") do
  Code.prepend_path(ebin)
end

Code.compile_file("lib/soundboard_web/live/soundboard_live.ex")

config = Config.Reader.read!("config/config.exs", env: :test)
Application.put_all_env(config, persistent: true)

repo_cfg = Application.fetch_env!(:soundboard, Soundboard.Repo)
db_file = "soundboard_test.db"

migrate_cfg =
  repo_cfg
  |> Keyword.put(:database, db_file)
  |> Keyword.put(:pool, DBConnection.ConnectionPool)
  |> Keyword.put(:pool_size, 2)

Application.put_env(:soundboard, :ecto_repos, [Soundboard.Repo], persistent: true)
Application.put_env(:soundboard, Soundboard.Repo, migrate_cfg, persistent: true)

{:ok, _} = Application.ensure_all_started(:telemetry)
{:ok, _} = Application.ensure_all_started(:ecto_sql)

case Ecto.Adapters.SQLite3.storage_up(migrate_cfg) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

{:ok, repo_pid} = Soundboard.Repo.start_link()
Ecto.Migrator.run(Soundboard.Repo, "priv/repo/migrations", :up, all: true)
GenServer.stop(repo_pid)

test_cfg =
  repo_cfg
  |> Keyword.put(:database, db_file)
  |> Keyword.put(:pool, Ecto.Adapters.SQL.Sandbox)
  |> Keyword.put(:pool_size, 1)

Application.put_env(:soundboard, Soundboard.Repo, test_cfg, persistent: true)

{:ok, _} = Application.ensure_all_started(:soundboard)
Ecto.Adapters.SQL.Sandbox.mode(Soundboard.Repo, :manual)

parse_target = fn target ->
  case Regex.run(~r/^(.*\.exs):(\d+)$/, target, capture: :all_but_first) do
    [path, line] ->
      {:ok, Path.expand(path), String.to_integer(line)}

    _ ->
      {:file, Path.expand(target)}
  end
end

targets = Enum.map(args, parse_target)

include_filters =
  Enum.flat_map(targets, fn
    {:ok, path, line} -> [location: {path, line}]
    _ -> []
  end)

ExUnit.start(autorun: false)
ExUnit.configure(include: include_filters)

targets
|> Enum.map(fn
  {:ok, path, _line} -> path
  {:file, path} -> path
end)
|> Enum.uniq()
|> Enum.each(&Code.require_file/1)

results = ExUnit.run()

if results.failures > 0 do
  System.halt(1)
else
  System.halt(0)
end
