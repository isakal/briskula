defmodule BriskulaWeb.GameLive.Index do
  use BriskulaWeb, :live_view

  alias Briskula.GameServer

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= case @view do %>
        <% :home -> %>
          <.live_component
            module={BriskulaWeb.GameLive.HomeComponent}
            id="home"
            room_code={@game_id}
          />

        <% :lobby -> %>
          <.live_component
            module={BriskulaWeb.GameLive.LobbyComponent}
            id="lobby"
            game_id={@game_id}
            username={@username}
            players={@players}
          />

        <% :game -> %>
          <.live_component
            module={BriskulaWeb.GameLive.GameComponent}
            id="game"
            game_id={@game_id}
            username={@username}
            mode={@mode}
          />
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:view, :home)
     |> assign(:username, nil)
     |> assign(:players, [])
     |> assign(:game_id, "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # IO.inspect(params)
    # IO.inspect(socket)

    case params do
      # Home view: / with no params
      %{} when map_size(params) == 0 ->
        {:noreply, socket}

      # Game/Lobby view: /:id
      %{"id" => game_id} ->

        case GameServer.get_game(game_id) do
          {:error, :game_not_found} ->
            {:noreply,
             socket
             |> push_navigate(to: "/")
             |> put_flash(:error, "Game #{game_id} not found")}

          game ->
            cond do
              # Check if the game is in the lobby phase
              game.phase == :lobby ->
                {:noreply,
                 socket
                 |> assign(:game_id, game_id)}

              # TODO: add a function for sending to player and spectator view
              game.phase == :playing ->
                {:noreply,
                 socket
                 |> assign(:game_id, game_id)}
            end
        end
    end
  end

  @impl true
  def handle_info({:create_game, username}, socket) do
    game_id = GameServer.generate_id()

    case GameServer.create_game(game_id, username) do
      {:ok, _pid} ->
        # Subscribe to PubSub
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Briskula.PubSub, game_id)
        end

        {:noreply,
         socket
         |> assign(:view, :lobby)
         |> assign(:username, username)
         |> assign(:game_id, game_id)
         |> push_patch(to: ~p"/#{game_id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create game")}
    end
  end

  @impl true
  def handle_info({:join_game, username, game_id}, socket) do
    case GameServer.get_game(game_id) do
      {:error, :game_not_found} ->
        {:noreply, put_flash(socket, :error, "Game '#{game_id}' not found")}

      _game ->
        # Try to join the game
        case GameServer.join_game(game_id, username) do
          {:ok, _view} ->
            # Subscribe to PubSub
            if connected?(socket) do
              Phoenix.PubSub.subscribe(Briskula.PubSub, game_id)
            end

            # Load fresh game state
            game = GameServer.get_game(game_id)

            {:noreply,
              socket
              |> assign(:view, :lobby)
              |> assign(:game, game)
              |> assign(:game_id, game_id)
              |> assign(:username, username)
              |> push_patch(to: ~p"/#{game_id}")}

          {:error, :game_full} ->
            {:noreply, put_flash(socket, :error, "Game is full")}

          {:error, :player_name_taken} ->
            {:noreply, put_flash(socket, :error, "Username already taken in this game")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to join game")}
        end
    end
  end

  @impl true
  def handle_info({:game_started}, socket) do
    # Game started, reload game state and switch to game view
    game = GameServer.get_game(socket.assigns.game_id)

    {:noreply,
      socket
      |> assign(game: game)
      |> assign(view: :game)}
  end

  # handle joins and leaves
  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    # Presence changed, just return socket - component will re-render

    game = GameServer.get_game(socket.assigns.game_id)

    {:noreply, assign(socket, :players, game.players)}
  end

  # propagating flashes
  @impl true
  def handle_info({:put_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  @impl true
  def terminate(_reason, socket) do
    # untrack the presence
    BriskulaWeb.Presence.untrack(
      self(),
      socket.assigns.game_id,
      socket.assigns.username
    )

    # leave the game (if in the :lobby phase)
    if socket.assigns.view == :lobby do
      GameServer.leave_game(
        socket.assigns.game_id,
        socket.assigns.username
        )
    end

    # delete the game if you are the last user so the memory doesn't fill with empty games
    case GameServer.get_game(socket.assigns.game_id) do
      {:error, _} ->
        {:noreply, socket}

      game ->
        if game.players == [] do
          [{pid, _}] = Registry.lookup(:BriskulaRegistry, socket.assigns.game_id)

          Process.exit(pid, :kill)
        end
      end
  end
end
