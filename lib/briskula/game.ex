defmodule Briskula.Game do
  @moduledoc """
  Pure functional game logic for Briscola card game.

  Supports 2-player (1v1) and 4-player (2V3) games with
  2-stage trick completion and game ending for better UX.
  """

  alias Briskula.FilteredGameView

  # Module attributes
  @suits [:coins, :spades, :cups, :batons]
  @ranks_strength [:ace, :three, :king, :knight, :knave, :"7", :"6", :"5", :"4", :"2"]
  @rank_index @ranks_strength
  |> Enum.with_index()
  |> Map.new(fn {rank, idx} -> {rank, idx} end)
  @ranks_points %{
    :ace => 11,
    :three => 10,
    :king => 4,
    :knight => 3,
    :knave => 2,
    :"7" => 0,
    :"6" => 0,
    :"5" => 0,
    :"4" => 0,
    :"2" => 0
  }

  # Types and struct
  @type status :: :continue | :game_over

  defstruct [
    # Game lifecycle
    # :lobby | :playing | :finished
    phase: :lobby,

    # Players and teams
    # player seating order list: (atoms / genserver ids)
    players: [],
    # nil (2 players) or %{team1: [...], team2: [...]} (4 players)
    teams: nil,

    # Cards and deck
    # remaining cards to draw
    deck: [],
    # the revealed trump card
    trump_card: nil,
    # %{player => [cards]} - each player's current hand
    hands: %{},
    # %{player => [cards]} - cards won by each player
    captured_cards: %{},
    # [{player, card}] - cards played in current trick
    table: [],

    # Turn management
    # queue of players for current trick
    turn_order: [],
    # whose turn it is to play
    current_player: nil
  ]

  # Public API

  @doc """
  Creates a new game lobby with a single player.

  ## Examples

      iex> Game.new("alice")
      {:ok, %Game{players: ["alice"], phase: :lobby, ...}}
  """
  @spec new(String.t()) :: {:ok, %__MODULE__{}}
  def new(player) when is_binary(player) do
    {:ok, %__MODULE__{players: [player], phase: :lobby}}
  end

  @doc """
  Adds a player to the game lobby.

  Returns `{:ok, updated_game}` on success,
  or `{:error, reason}` if validation fails.
  """
  @spec join_game(%__MODULE__{}, String.t()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def join_game(%__MODULE__{} = game, player) when is_binary(player) do
    with {:ok, game} <- validate_lobby_phase(game),
         {:ok, game} <- validate_game_not_full(game),
         {:ok, game} <- validate_unique_player_name(game, player) do
      {:ok, %{game | players: game.players ++ [player]}}
    end
  end

  @doc """
  Removes a player from the game lobby.

  Returns `{:ok, updated_game}` on success,
  or `{:error, reason}` if validation fails.
  """
  @spec leave_game(%__MODULE__{}, String.t()) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def leave_game(%__MODULE__{} = game, player) when is_binary(player) do
    with {:ok, game} <- validate_lobby_phase(game),
         {:ok, game} <- validate_player_in_game(game, player) do
      {:ok, %{game | players: List.delete(game.players, player)}}
    end
  end

  @doc """
  Starts the game by dealing cards and setting up teams.

  Returns `{:ok, game}` on success,
  or `{:error, reason}` if validation fails.
  """
  @spec start(%__MODULE__{}) :: {:ok, %__MODULE__{}} | {:error, atom()}
  def start(%__MODULE__{} = game) do
    with {:ok, game} <- validate_lobby_phase(game),
         {:ok, game} <- validate_player_count_for_start(game) do
      {:ok,
       game
       |> setup_teams()
       |> initialize_hands()
       |> initialize_captured_cards()
       |> setup_deck()
       |> deal_cards()
       |> setup_trump_card()
       |> start_game_final()}
    end
  end

  @doc """
  Play a card from player's hand, placing it on the table.

  Returns `{:continue, updated_game}` for normal moves,
  `{:trick_complete, game}` when a trick is complete but not yet resolved,
  or `{:error, reason}` if validation fails.
  """
  @spec play_card(%__MODULE__{}, String.t(), %Briskula.Card{}) ::
          {:continue, %__MODULE__{}}
          | {:trick_complete, %__MODULE__{}}
          | {:error, atom()}
  def play_card(%__MODULE__{} = game, player, %Briskula.Card{} = card) do
    with {:ok, game} <- validate_game_phase(game),
         {:ok, game} <- validate_turn(game, player),
         {:ok, game} <- validate_card_in_hand(game, player, card) do
      game
      |> remove_card_from_hand(player, card)
      |> add_card_to_table(player, card)
      |> advance_turn()
      |> mark_trick_status()
    end
  end

  @doc """
  Resolves a completed trick. Should be called after a trick_complete state.

  Returns `{:continue, game}` for normal trick resolution,
  or `{:game_complete, game}` when game is complete but not finalized.
  """
  @spec resolve_trick(%__MODULE__{}) ::
          {:continue, %__MODULE__{}}
          | {:game_complete, %__MODULE__{}}
          | {:error, atom()}
  def resolve_trick(%__MODULE__{} = game) do
    if game.turn_order != [] do
      {:error, :trick_not_complete}
    else
      winner = determine_trick_winner(game)

      game
      |> set_current_player(winner)
      |> capture_trick_cards(winner)
      |> reset_table()
      |> rotate_players(winner)
      |> deal_cards(1)
      |> mark_game_status()
    end
  end

  @doc """
  Finalizes a completed game by calculating final scores.

  Returns `{:game_over, game, score_map}`
  """
  @spec finalize_game(%__MODULE__{}) ::
          {:game_over, %__MODULE__{}, map()}
          | {:error, atom()}
  def finalize_game(%__MODULE__{} = game) do
    if game_over?(game) do
      {:game_over, game, score(game)}
    else
      {:error, :game_not_complete}
    end
  end


  @spec filter_view(%__MODULE__{}, String.t()) :: %FilteredGameView{}
  def filter_view(%__MODULE__{} = game, player) do
    %FilteredGameView{
      phase: game.phase,
      players: game.players,
      teams: game.teams,
      deck_count: length(game.deck),
      trump_card: game.trump_card,
      hand: Map.get(game.hands, player, []),
      hand_counts: Enum.into(game.hands, %{}, fn {p, hand} -> {p, length(hand)} end),
      captured_card_counts: Enum.into(game.captured_cards, %{}, fn {p, cards} -> {p, length(cards)} end),
      table: game.table,
      turn_order: game.turn_order,
      current_player: game.current_player
    }
  end

  # Private implementation

  # Game setup pipeline functions

  defp setup_teams(%{players: players} = game) do
    teams =
      case length(players) do
        4 ->
          [p1, p2, p3, p4] = players
          %{team1: [p1, p3], team2: [p2, p4]}

        2 ->
          nil
      end

    %{game | teams: teams}
  end

  defp initialize_captured_cards(%{players: players} = game) do
    captured = Map.new(players, fn player -> {player, []} end)
    %{game | captured_cards: captured}
  end

  defp initialize_hands(%{players: players} = game) do
    hands = Map.new(players, fn player -> {player, []} end)
    %{game | hands: hands}
  end

  defp setup_deck(game) do
    deck = build_deck()
    %{game | deck: deck}
  end

  defp deal_cards(%__MODULE__{} = game, n_cards \\ 3) do
    game
    |> get_player_order()
    |> deal_cards_to_players(game.deck, n_cards)
    |> then(fn {drawn_hands, remaining_deck} ->
      game
      |> update_player_hands(drawn_hands)
      |> Map.put(:deck, remaining_deck)
    end)
  end

  defp get_player_order(%{phase: :playing, turn_order: turn_order}), do: turn_order
  defp get_player_order(%{players: players}), do: players

  defp deal_cards_to_players(players, deck, n_cards) do
    players
    |> Enum.map_reduce(deck, fn player, current_deck ->
      {cards, remaining_deck} = Enum.split(current_deck, n_cards)
      {{player, cards}, remaining_deck}
    end)
    |> then(fn {player_card_pairs, final_deck} ->
      {Map.new(player_card_pairs), final_deck}
    end)
  end

  defp update_player_hands(game, drawn_hands) do
    new_hands =
      drawn_hands
      |> Enum.reject(fn {_player, cards} -> cards == [] end)
      |> Enum.reduce(game.hands, fn {player, cards}, acc ->
        Map.update!(acc, player, &(&1 ++ cards))
      end)

    %{game | hands: new_hands}
  end

  defp setup_trump_card(%{deck: [trump_card | deck_tail]} = game) do
    # take the trump card from the deck and put it at the end of the deck (trump card is last card to be picked up)
    deck_final = deck_tail ++ [trump_card]
    %{game | trump_card: trump_card, deck: deck_final}
  end

  defp start_game_final(%{players: players} = game) do
    %{game | phase: :playing, turn_order: players, current_player: List.first(players)}
  end

  # Game validation functions

  defp validate_lobby_phase(%{phase: :lobby} = game), do: {:ok, game}
  defp validate_lobby_phase(%{phase: :playing}), do: {:error, :game_already_started}
  defp validate_lobby_phase(%{phase: :finished}), do: {:error, :game_already_started}

  defp validate_game_not_full(%{players: players} = game) when length(players) < 4 do
    {:ok, game}
  end
  defp validate_game_not_full(_game), do: {:error, :game_full}

  defp validate_unique_player_name(%{players: players} = game, player) do
    if player in players do
      {:error, :player_name_taken}
    else
      {:ok, game}
    end
  end

  defp validate_player_in_game(%{players: players} = game, player) do
    if player in players do
      {:ok, game}
    else
      {:error, :player_not_in_game}
    end
  end

  defp validate_player_count_for_start(%{players: players} = game) when length(players) in [2, 4] do
    {:ok, game}
  end
  defp validate_player_count_for_start(_game), do: {:error, :invalid_player_count}

  defp validate_game_phase(%{phase: :playing} = game), do: {:ok, game}
  defp validate_game_phase(%{phase: :lobby}), do: {:error, :game_not_started}
  defp validate_game_phase(%{phase: :finished}), do: {:error, :game_over}

  defp validate_turn(game, player) do
    cond do
      game.turn_order == [] ->
        {:error, :trick_complete}

      game.current_player == player ->
        {:ok, game}

      true ->
        {:error, :not_players_turn}
    end
  end

  defp validate_card_in_hand(game, player, card) do
    player_hand = Map.get(game.hands, player, [])

    if card in player_hand do
      {:ok, game}
    else
      {:error, :card_not_in_hand}
    end
  end

  # Card play pipeline functions

  defp remove_card_from_hand(game, player, card) do
    new_hand =
      game.hands
      |> Map.fetch!(player)
      |> List.delete(card)

    %{game | hands: Map.put(game.hands, player, new_hand)}
  end

  defp add_card_to_table(game, player, card) do
    %{game | table: game.table ++ [{player, card}]}
  end

  defp advance_turn(game) do
    case game.turn_order do
      [_current | rest] ->
        %{game | turn_order: rest, current_player: List.first(rest)}

      # Shouldn't happen, but safe fallback
      [] ->
        game
    end
  end


  defp mark_trick_status(%{turn_order: []} = game) do
    {:trick_complete, game}
  end

  defp mark_trick_status(game) do
    {:continue, game}
  end

  # Trick resolution pipeline functions

  defp determine_trick_winner(%__MODULE__{table: table, trump_card: trump_card} = _game) do
    [{_lead_player, %{suit: lead_suit}} | _] = table

    # helper to get rank index
    rank_idx = fn rank -> Map.fetch!(@rank_index, rank) end

    # build candidates list with comparison value
    candidates =
      Enum.map(table, fn {player, %Briskula.Card{rank: r, suit: s} = card} ->
        {player, card, rank_idx.(r), s}
      end)

    # determine if trump card was played
    trump_played = Enum.any?(candidates, fn {_, _, _, suit} -> suit == trump_card.suit end)

    # filter contenders by suit (trump or lead)
    contenders =
      cond do
        trump_played -> Enum.filter(candidates, fn {_, _, _, suit} -> suit == trump_card.suit end)
        true -> Enum.filter(candidates, fn {_, _, _, suit} -> suit == lead_suit end)
      end

    # pick contender with lowest rank index (strongest)
    {winner, _, _, _} = Enum.min_by(contenders, fn {_, _, idx, _} -> idx end)
    winner
  end

  defp set_current_player(game, winner) do
    %{game | current_player: winner}
  end

  defp capture_trick_cards(game, winner) do
    trick_cards = Enum.map(game.table, fn {_p, c} -> c end)

    updated_captured =
      Map.update(game.captured_cards, winner, trick_cards, fn lst -> lst ++ trick_cards end)

    %{game | captured_cards: updated_captured}
  end

  defp reset_table(game) do
    %{game | table: []}
  end

  defp rotate_players(game, winner) do
    {left, right} = Enum.split_while(game.players, &(&1 != winner))
    new_turn_order = right ++ left
    %{game | turn_order: new_turn_order}
  end

  defp mark_game_status(game) do
    if game_over?(game) do
      {:game_complete, %{game | phase: :finished}}
    else
      {:continue, game}
    end
  end

  # Helper functions

  defp build_deck do
    @suits
    |> Enum.flat_map(fn suit ->
      Enum.map(@ranks_strength, fn rank -> %Briskula.Card{suit: suit, rank: rank} end)
    end)
    |> Enum.shuffle()
  end

  defp game_over?(%__MODULE__{} = game) do
    game.deck == [] and Enum.all?(game.hands, fn {_p, h} -> h == [] end)
  end

  defp score(%__MODULE__{} = game) do
    calc = fn cards -> Enum.map(cards, &@ranks_points[&1.rank]) |> Enum.sum() end

    case game.teams do
      nil ->
        Enum.into(game.captured_cards, %{}, fn {p, cards} -> {p, calc.(cards)} end)

      teams ->
        Enum.into(teams, %{}, fn {team_key, members} ->
          team_cards = members |> Enum.flat_map(&Map.get(game.captured_cards, &1, []))
          {team_key, calc.(team_cards)}
        end)
    end
  end
end
