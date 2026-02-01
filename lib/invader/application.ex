defmodule Invader.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      InvaderWeb.Telemetry,
      Invader.Vault,
      Invader.Repo,
      {AshAuthentication.Supervisor, otp_app: :invader},
      Invader.Settings,
      # Registry for tracking running mission processes
      {Registry, keys: :unique, name: Invader.MissionRegistry},
      {DNSCluster, query: Application.get_env(:invader, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:invader, :ash_domains),
         Application.fetch_env!(:invader, Oban)
       )},
      {Phoenix.PubSub, name: Invader.PubSub},
      # Start a worker by calling: Invader.Worker.start_link(arg)
      # {Invader.Worker, arg},
      # Start to serve requests, typically the last entry
      InvaderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Invader.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InvaderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
