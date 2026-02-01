ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Invader.Repo, :manual)

# Mimic setup - copy modules for mocking
Mimic.copy(Invader.Connections.GitHub.Executor)
Mimic.copy(Invader.Connections.GitHub.TokenGenerator)
Mimic.copy(Phoenix.Token)
Mimic.copy(Req)
Mimic.copy(System)
