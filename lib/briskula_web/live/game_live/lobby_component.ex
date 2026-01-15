defmodule BriskulaWeb.GameLive.LobbyComponent do
  use BriskulaWeb, :live_component

  alias BriskulaWeb.Presence
  alias Briskula.GameServer

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-view max-w-4xl mx-auto mt-10">
      <.header>
        Game Lobby
      </.header>

      <%!-- Room Code Display --%>
      <div class="mt-6 bg-gradient-to-r from-blue-50 to-purple-50 rounded-xl p-6 border-2 border-blue-200">
        <div class="text-center">
          <p class="text-sm font-medium text-gray-600 mb-2">Room Code</p>
          <div
            id="room-code-container"
            phx-click="copy_room_code"
            phx-target={@myself}
            class="inline-flex items-center gap-3 px-6 py-3 bg-white rounded-lg shadow-sm cursor-pointer hover:bg-gray-50 transition-colors group"
          >
            <span class="text-4xl font-bold text-gray-900 tracking-wider font-mono">
              {@game_id}
            </span>
            <.icon name="hero-clipboard-document" class="w-6 h-6 text-gray-400 group-hover:text-blue-600 transition-colors" />
          </div>
          <p class="text-xs text-gray-500 mt-2">Click to copy</p>
          <div
            id="copy-feedback"
            class="hidden mt-2 text-sm text-green-600 font-medium"
            phx-click={JS.hide(to: "#copy-feedback")}
          >
            ✓ Copied to clipboard!
          </div>
        </div>
      </div>

      <div class="mt-8 grid">
        <%!-- Always show two team panes for 1v1 or 2v2 --%>
        <div class="grid grid-cols-2 gap-6 mb-8">
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-bold mb-4 text-blue-600">Team 1</h3>
            <ul class="space-y-2">
              <li
                :for={player <- Enum.take_every(@players, 2)}
                class="flex items-center gap-3 p-3 bg-blue-50 rounded"
              >
                <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                  {String.first(player)}
                </div>
                <div class="flex-1 text-gray-600 font-medium">
                  {player}
                  <%= if player == @username do %>
                    <span class="text-sm text-gray-500 font-normal">(you)</span>
                  <% end %>
                  <%= if player == List.first(@players) do %>
                    <span class="text-sm text-blue-600">👑</span>
                  <% end %>
                </div>
                <!-- Online icon -->
                <%= if Enum.member?(@present_users, player) do %>
                  <span class="text-green-500">●</span>
                <% else %>
                  <span class="text-gray-300">●</span>
                <% end %>
              </li>
            </ul>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-bold mb-4 text-red-600">Team 2</h3>
            <ul class="space-y-2">
              <li
                :for={player <- Enum.drop(@players, 1) |> Enum.take_every(2)}
                class="flex items-center gap-3 p-3 bg-red-50 rounded"
              >
                <div class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center">
                  {String.first(player)}
                </div>
                <div class="flex-1 text-gray-600 font-medium">
                  {player}
                  <%= if player == @username do %>
                    <span class="text-sm text-gray-500 font-normal">(you)</span>
                  <% end %>
                </div>
                <!-- Online icon -->
                <%= if Enum.member?(@present_users, player) do %>
                  <span class="text-green-500">●</span>
                <% else %>
                  <span class="text-gray-300">●</span>
                <% end %>
              </li>
            </ul>
          </div>
        </div>

        <%= if @is_creator and length(@players) in [2, 4] do %>
          <.button
            phx-click="start_game"
            phx-target={@myself}
            variant="primary"
          >
            Start Game ({length(@players)} players)
          </.button>
        <% else %>
          <div class="text-center text-gray-500 mt-6">
            <%= cond do %>
              <% @is_creator and length(@players) not in [2, 4] -> %>
                Waiting for 2 or 4 players to start the game...
              <% true -> %>
                Waiting for the host to start the game...
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    game_id = assigns.game_id
    username = assigns.username

    # Track presence on first mount (connected? not available in LiveComponent)
    if not Map.get(socket.assigns, :tracked, false) do
      Presence.track(self(), game_id, username, %{})
    end

    # Get list of present users
    present_users = get_present_users(game_id)

    game = Briskula.GameServer.get_game(game_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tracked, true)
     |> assign(:present_users, present_users)
     |> assign(:is_creator, username == List.first(game.players))}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game_id = socket.assigns.game_id

    case GameServer.start_game(game_id) do
      {:ok, _game} ->
        # Broadcast game started
        Phoenix.PubSub.broadcast(
          Briskula.PubSub,
          game_id,
          {:game_started}
        )

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start game: #{reason}")}
    end
  end

  @impl true
  def handle_event("copy_room_code", _params, socket) do
    game_id = socket.assigns.game_id

    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: game_id})
     |> push_event("show-copy-feedback", %{})}
  end

  defp get_present_users(game_id) do
    Presence.list(game_id)
    |> Enum.map(fn {username, _} -> username end)
  end
end
