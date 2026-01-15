defmodule BriskulaWeb.GameLive.GameComponent do
  use BriskulaWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-view max-w-6xl mx-auto mt-10">
      <.header>
        Game in Progress
        <:subtitle>Game ID: {@game_id}</:subtitle>
      </.header>

      <div class="mt-8 bg-white rounded-lg shadow p-8">
        <div class="text-center text-gray-500">
          <p class="text-xl mb-4">🎴 Briškula</p>
          <p>Game interface coming soon...</p>

          <%= if @mode == :spectator do %>
            <div class="mt-6 bg-yellow-100 border border-yellow-400 px-4 py-2 rounded">
              👁️ Spectator Mode - You are watching this game
            </div>
          <% else %>
            <div class="mt-6">
              <p class="font-semibold">Playing as: {@username}</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end
end
