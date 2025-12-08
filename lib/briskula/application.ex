defmodule Briskula.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BriskulaWeb.Telemetry,
      {Phoenix.PubSub, name: Briskula.PubSub},
      {Registry, keys: :unique, name: :BriskulaRegistry},
      {DynamicSupervisor, name: Briskula.GameSupervisor, strategy: :one_for_one},
      {DNSCluster, query: Application.get_env(:briskula, :dns_cluster_query) || :ignore},
      BriskulaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Briskula.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BriskulaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
