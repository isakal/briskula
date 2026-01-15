defmodule Briskula.GameServer do
  @moduledoc """
  A GenServer that manages a Briscola game with lobby support.

  ## Lobby Flow

  1. Create a game with one player: `start_link(game_id, player)`
  2. Other players join: `join_game(game_id, player)`
  3. Start the game when ready: `start_game(game_id)`
  4. Play cards and resolve tricks as usual

  The game starts in `:lobby` phase and transitions to `:playing` when started.
  """

  use GenServer
  alias Briskula.Game

  # Registry name
  @registry_name :BriskulaRegistry

  # Alphabet used for ID generation
  @alphabet [?0..?9, ?A..?Z, ?a..?z]
    |> Enum.concat()
    |> Enum.to_list()
    |> List.to_string()

  defp via_tuple(game_id) do
    {:via, Registry, {@registry_name, game_id}}
  end

  @doc """
  Generates a unique game ID that doesn't exist in the registry.

  Uses Nanoid to generate an 8-character ID and checks the registry
  to ensure uniqueness. If a collision occurs, generates a new ID recursively.

  ## Examples

      iex> game_id = Briskula.GameServer.generate_id()
      iex> is_binary(game_id)
      true
  """
  def generate_id() do
    id = Nanoid.generate(4, @alphabet)

    case Registry.lookup(@registry_name, id) do
      [] ->
        # ID doesn't exist, it's unique
        id

      _existing ->
        # ID already exists, generate a new one
        generate_id()
    end
  end

  @doc """
  Starts a game server with a lobby containing a single player.

  ## Examples

      iex> GameServer.start_link("game123", "alice")
      {:ok, pid}
  """
  def start_link(game_id, player) when is_binary(player) do
    GenServer.start_link(__MODULE__, player, name: via_tuple(game_id))
  end

  @doc """
  Creates a new game with a lobby containing a single player.
  Starts the game under the DynamicSupervisor.

  ## Examples

      iex> GameServer.create_game("game123", "alice")
      {:ok, pid}
  """
  def create_game(game_id, player) when is_binary(player) do
    child_spec = %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [game_id, player]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(Briskula.GameSupervisor, child_spec)
  end

  @doc """
  Gets the full game state.

  Returns the complete game state including all players' hands.
  This is typically used for debugging or admin purposes.

  ## Examples

      iex> GameServer.get_game("game123")
      %Game{...}
  """
  def get_game(game_id) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:get_game})
    end
  end

  @doc """
  Gets a filtered game view for a specific player.

  Returns a filtered view that only shows the requesting player's hand
  while hiding other players' cards. Shows card counts for other players.

  ## Examples

      iex> GameServer.get_game("game123", "alice")
      %FilteredGameView{...}
  """
  def get_game(game_id, player) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:get_game, player})
      end
  end

  @doc """
  Adds a player to the game lobby.

  Returns the filtered game view for the joining player or an error.

  ## Examples

      iex> GameServer.join_game("game123", "bob")
      {:ok, filtered_game_view}
  """
  def join_game(game_id, player) when is_binary(player) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:join_game, player})
    end
  end

  @doc """
  Removes a player from the game lobby.

  Returns the filtered game view for the leaving player or an error.

  ## Examples

      iex> GameServer.leave_game("game123", "bob")
      {:ok, filtered_game_view}
  """
  def leave_game(game_id, player) when is_binary(player) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:leave_game, player})
    end
  end

  @doc """
  Starts the game, transitioning from lobby to playing phase.

  Validates player count (2 or 4) and deals cards.

  ## Examples

      iex> GameServer.start_game("game123")
      {:ok, game}
  """
  def start_game(game_id) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:start_game})
    end
  end

  @doc """
  Plays a card for a player in the game.

  The player must be the current player and the card must be in their hand.
  Returns a filtered view for the player showing the updated game state.

  ## Examples

      iex> GameServer.play_card("game123", "alice", %Card{suit: :spades, rank: :ace})
      {:continue, %FilteredGameView{...}}

      iex> GameServer.play_card("game123", "alice", last_card)
      {:trick_complete, %FilteredGameView{...}}
  """
  def play_card(game_id, player, card) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:play_card, player, card})
    end
  end

  @doc """
  Resolves a completed trick.

  Determines the winner, awards cards, deals new cards if available,
  and sets up the next trick.

  ## Examples

      iex> GameServer.resolve_trick("game123")
      :continue

      iex> GameServer.resolve_trick("game123")  # last trick
      :game_complete
  """
  def resolve_trick(game_id) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:resolve_trick})
    end
  end

  @doc """
  Finalizes the game and calculates scores.

  Can only be called when the game is complete (all cards played).
  Returns final scores for players or teams.

  ## Examples

      iex> GameServer.finalize_game("game123")
      {:game_over, %{p1: 61, p2: 59}}

      iex> GameServer.finalize_game("game123")  # 2v2
      {:game_over, %{team1: 65, team2: 55}}
  """
  def finalize_game(game_id) do
    case Registry.lookup(@registry_name, game_id) do
      [] ->
        {:error, :game_not_found}
      [{pid, _}] ->
        GenServer.call(pid, {:finalize_game})
    end
  end


  @impl true
  def init(player) when is_binary(player) do
    {:ok, game} = Game.new(player)
    {:ok, game}
  end

  @impl true
  def handle_call({:get_game}, _from, %Game{} = game) do
    {:reply, game, game}
  end

  @impl true
  def handle_call({:get_game, player}, _from, %Game{} = game) do
    # return filtered view but store whole game
    fgame = Game.filter_view(game, player)
    {:reply, fgame, game}
  end

  @impl true
  def handle_call({:join_game, player}, _from, %Game{} = game) do
    case Game.join_game(game, player) do
      {:ok, updated_game} ->
        # Return filtered view for the joining player
        {:reply, {:ok, Game.filter_view(updated_game, player)}, updated_game}

      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end

  @impl true
  def handle_call({:leave_game, player}, _from, %Game{} = game) do
    case Game.leave_game(game, player) do
      {:ok, updated_game} ->
        # Return filtered view for the leaving player
        {:reply, {:ok, Game.filter_view(updated_game, player)}, updated_game}

      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end

  @impl true
  def handle_call({:start_game}, _from, %Game{} = game) do
    case Game.start(game) do
      {:ok, started_game} ->
        {:reply, {:ok, started_game}, started_game}

      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end

  @impl true
  def handle_call({:play_card, player, card}, _from, %Game{} = game)
      when is_binary(player) do
    case Game.play_card(game, player, card) do
      # if :continue, return filtered view but store whole game
      {:continue, game} ->
        {
          :reply,
          {
            :continue,
            Game.filter_view(game, player)
          },
          game
        }

      {:trick_complete, game} ->
        # broadcast to all players that trick is complete
        {
          :reply,
          {
            :trick_complete,
            Game.filter_view(game, player)
          },
          game
        }

      # if :error, keep the genserver running and return the error message
      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end

  @impl true
  def handle_call({:resolve_trick}, _from, %Game{} = game) do
    case Game.resolve_trick(game) do
      {:continue, game} ->
        {:reply, :continue, game}

      {:game_complete, game} ->
        {:reply, :game_complete, game}

      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end

  @impl true
  def handle_call({:finalize_game}, _from, %Game{} = game) do
    case Game.finalize_game(game) do
      {:game_over, game, score_map} ->
        {:reply, {:game_over, score_map}, game}

      {:error, reason} ->
        {:reply, {:error, reason}, game}
    end
  end
end
