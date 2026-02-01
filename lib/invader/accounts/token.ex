defmodule Invader.Accounts.Token do
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Accounts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  sqlite do
    table "tokens"
    repo Invader.Repo
  end

  actions do
    defaults [:read, :destroy]
  end
end
