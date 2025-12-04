defmodule BriskulaWeb.GameLive.Game do
  use BriskulaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>

    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do

    # # IO.inspect(id)

    IO.inspect(socket)

    {:ok, socket}
  end
end
