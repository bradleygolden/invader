defmodule Invader.Accounts do
  use Ash.Domain,
    otp_app: :invader,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Invader.Accounts.User
    resource Invader.Accounts.Token
  end
end
