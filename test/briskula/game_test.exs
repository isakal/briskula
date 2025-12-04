defmodule Briskula.GameTest do
  use ExUnit.Case, async: true
  # doctest Briskula

  alias Briskula.Fixtures

  # ========================================
  # Tests for Briskula.Game.new/1, join_game/2, start/1
  # ========================================

  describe "Game.new/1 - creates lobby -->" do
    test "creates a lobby with single player" do
      assert {:ok, game} = Briskula.Game.new("p1")

      # Verify player is set correctly
      assert game.players == ["p1"]

      # Verify phase is :lobby
      assert game.phase == :lobby

      # Verify game is not initialized yet
      assert game.deck == []
      assert game.trump_card == nil
      assert game.hands == %{}
      assert game.captured_cards == %{}
      assert game.table == []
      assert game.turn_order == []
      assert game.current_player == nil
    end
  end

  describe "Game.join_game/2 - happy path -->" do
    test "adds second player to lobby" do
      {:ok, game} = Briskula.Game.new("p1")
      assert {:ok, game} = Briskula.Game.join_game(game, "p2")

      assert game.players == ["p1", "p2"]
      assert game.phase == :lobby
    end

    test "adds up to 4 players to lobby" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p3") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p4") end)

      assert game.players == ["p1", "p2", "p3", "p4"]
      assert game.phase == :lobby
    end
  end

  describe "Game.join_game/2 - unhappy path -->" do
    test "rejects join when game is full (4 players)" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p3") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p4") end)

      assert {:error, :game_full} = Briskula.Game.join_game(game, "p5")
    end

    test "rejects join when player name already taken" do
      {:ok, game} = Briskula.Game.new("p1")
      {:ok, game} = Briskula.Game.join_game(game, "p2")

      assert {:error, :player_name_taken} = Briskula.Game.join_game(game, "p1")
      assert {:error, :player_name_taken} = Briskula.Game.join_game(game, "p2")
    end

    test "rejects join when game already started" do
      {:ok, game} = Briskula.Game.new("p1")
      {:ok, game} = Briskula.Game.join_game(game, "p2")
      {:ok, game} = Briskula.Game.start(game)

      assert {:error, :game_already_started} = Briskula.Game.join_game(game, "p3")
    end
  end

  describe "Game.start/1 - happy path (1v1) -->" do
    test "starts a valid 1v1 game with 2 players" do
      {:ok, game} = Briskula.Game.new("p1")
      {:ok, game} = Briskula.Game.join_game(game, "p2")
      assert {:ok, game} = Briskula.Game.start(game)

      # Verify players are set correctly
      assert game.players == ["p1", "p2"]

      # Verify no teams for 1v1
      assert game.teams == nil

      # Verify phase is :playing
      assert game.phase == :playing

      # Verify deck size: 40 cards - 6 dealt (3 per player) = 34 remaining
      assert length(game.deck) == 34

      # Verify trump card exists and is the last card in deck
      assert game.trump_card != nil
      assert game.trump_card == List.last(game.deck)

      # Verify each player has 3 cards
      assert length(game.hands["p1"]) == 3
      assert length(game.hands["p2"]) == 3

      # Verify cards are unique (no duplicates dealt)
      all_dealt_cards = game.hands["p1"] ++ game.hands["p2"]
      assert length(all_dealt_cards) == length(Enum.uniq(all_dealt_cards))

      # Verify captured_cards initialized
      assert game.captured_cards == %{"p1" => [], "p2" => []}

      # Verify table is empty
      assert game.table == []

      # Verify turn order
      assert game.turn_order == ["p1", "p2"]
      assert game.current_player == "p1"
    end

    test "deals different cards on successive calls" do
      {:ok, game1} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.start(g) end)

      {:ok, game2} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.start(g) end)

      # Because deck is shuffled, games should be different (statistically)
      # Check that at least one hand is different
      refute game1.hands["p1"] == game2.hands["p1"] or
             game1.hands["p2"] == game2.hands["p2"] or
             game1.trump_card == game2.trump_card
    end
  end

  describe "Game.start/1 - happy path (2v2) -->" do
    test "starts a valid 2v2 game with 4 players" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p3") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p4") end)

      assert {:ok, game} = Briskula.Game.start(game)

      # Verify players are set correctly
      assert game.players == ["p1", "p2", "p3", "p4"]

      # Verify teams for 2v2: team1 = [p1, p3], team2 = [p2, p4]
      assert game.teams == %{
        team1: ["p1", "p3"],
        team2: ["p2", "p4"]
      }

      # Verify phase is :playing
      assert game.phase == :playing

      # Verify deck size: 40 cards - 12 dealt (3 per player × 4) = 28 remaining
      assert length(game.deck) == 28

      # Verify trump card exists and is the last card in deck
      assert game.trump_card != nil
      assert game.trump_card == List.last(game.deck)

      # Verify each player has 3 cards
      assert length(game.hands["p1"]) == 3
      assert length(game.hands["p2"]) == 3
      assert length(game.hands["p3"]) == 3
      assert length(game.hands["p4"]) == 3

      # Verify cards are unique (no duplicates dealt)
      all_dealt_cards =
        game.hands["p1"] ++
        game.hands["p2"] ++
        game.hands["p3"] ++
        game.hands["p4"]
      assert length(all_dealt_cards) == length(Enum.uniq(all_dealt_cards))

      # Verify captured_cards initialized for all players
      assert game.captured_cards == %{
        "p1" => [],
        "p2" => [],
        "p3" => [],
        "p4" => []
      }

      # Verify table is empty
      assert game.table == []

      # Verify turn order
      assert game.turn_order == ["p1", "p2", "p3", "p4"]
      assert game.current_player == "p1"
    end

    test "teams are assigned correctly based on seating order" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p3") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p4") end)
        |> then(fn {:ok, g} -> Briskula.Game.start(g) end)

      # First and third player on team1
      assert "p1" in game.teams.team1
      assert "p3" in game.teams.team1

      # Second and fourth player on team2
      assert "p2" in game.teams.team2
      assert "p4" in game.teams.team2
    end
  end

  describe "Game.start/1 - unhappy path -->" do
    test "rejects start with single player" do
      {:ok, game} = Briskula.Game.new("p1")

      assert {:error, :invalid_player_count} = Briskula.Game.start(game)
    end

    test "rejects start with 3 players" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p3") end)

      assert {:error, :invalid_player_count} = Briskula.Game.start(game)
    end

    test "rejects start when game already started" do
      {:ok, game} =
        Briskula.Game.new("p1")
        |> then(fn {:ok, g} -> Briskula.Game.join_game(g, "p2") end)
        |> then(fn {:ok, g} -> Briskula.Game.start(g) end)

      assert {:error, :game_already_started} = Briskula.Game.start(game)
    end
  end

  # ========================================
  # Tests for Briskula.Game.play_card/3
  # ========================================

  describe "Game.play_card/3 - happy path (1v1) -->" do
    test "plays card successfully, trick continues" do
      game = Fixtures.game_1v1()
      card_to_play = hd(game.hands["p1"])

      assert {:continue, updated_game} = Briskula.Game.play_card(game, "p1", card_to_play)

      # Card moved from hand to table
      assert length(updated_game.hands["p1"]) == 2
      assert card_to_play not in updated_game.hands["p1"]
      assert length(updated_game.table) == 1
      assert {"p1", card_to_play} in updated_game.table

      # Turn advances to next player
      assert updated_game.current_player == "p2"
      assert updated_game.turn_order == ["p2"]
    end

    test "plays card successfully, trick completes" do
      # Setup game where p2 is last to play
      card_p1 = Fixtures.card(:batons, :three)
      card_p2 = Fixtures.card(:cups, :"7")

      game = Fixtures.game_1v1(
        table: [{"p1", card_p1}],
        turn_order: ["p2"],
        current_player: "p2",
        hands: %{
          "p1" => [Fixtures.card(:spades, :knight), Fixtures.card(:spades, :ace)],
          "p2" => [card_p2, Fixtures.card(:cups, :"6"), Fixtures.card(:spades, :king)]
        }
      )

      assert {:trick_complete, updated_game} =
        Briskula.Game.play_card(game, "p2", card_p2)

      # Card moved to table
      assert length(updated_game.table) == 2
      assert {"p2", card_p2} in updated_game.table

      # Turn order is empty (trick complete)
      assert updated_game.turn_order == []
      assert updated_game.current_player == nil
    end
  end

  describe "Game.play_card/3 - happy path (2v2) -->" do
    test "plays card successfully, trick continues" do
      game = Fixtures.game_2v2()
      card_to_play = hd(game.hands["p1"])

      assert {:continue, updated_game} = Briskula.Game.play_card(game, "p1", card_to_play)

      # Card moved from hand to table
      assert length(updated_game.hands["p1"]) == 2
      assert card_to_play not in updated_game.hands["p1"]
      assert length(updated_game.table) == 1

      # Turn advances to next player
      assert updated_game.current_player == "p2"
      assert updated_game.turn_order == ["p2", "p3", "p4"]
    end

    test "plays card successfully, trick completes" do
      # Setup game where p4 is last to play
      card_p1 = Fixtures.card(:batons, :three)
      card_p2 = Fixtures.card(:cups, :"7")
      card_p3 = Fixtures.card(:coins, :three)
      card_p4 = Fixtures.card(:batons, :"7")

      game = Fixtures.game_2v2(
        table: [{"p1", card_p1}, {"p2", card_p2}, {"p3", card_p3}],
        turn_order: ["p4"],
        current_player: "p4",
        hands: %{
          "p1" => [Fixtures.card(:spades, :knight)],
          "p2" => [Fixtures.card(:cups, :"6")],
          "p3" => [Fixtures.card(:coins, :knight)],
          "p4" => [card_p4, Fixtures.card(:batons, :"6")]
        }
      )

      assert {:trick_complete, updated_game} =
        Briskula.Game.play_card(game, "p4", card_p4)

      # Card moved to table
      assert length(updated_game.table) == 4
      assert {"p4", card_p4} in updated_game.table

      # Turn order is empty (trick complete)
      assert updated_game.turn_order == []
      assert updated_game.current_player == nil
    end
  end

  describe "Game.play_card/3 - unhappy path -->" do
    test "rejects play when game not started" do
      game = Fixtures.game_1v1(phase: :lobby)
      card = hd(game.hands["p1"])

      assert {:error, :game_not_started} =
        Briskula.Game.play_card(game, "p1", card)
    end

    test "rejects play when game finished" do
      game = Fixtures.game_1v1(phase: :finished)
      card = hd(game.hands["p1"])

      assert {:error, :game_over} =
        Briskula.Game.play_card(game, "p1", card)
    end

    test "rejects play when trick already complete" do
      game = Fixtures.game_1v1(
        turn_order: [],
        current_player: nil
      )
      card = hd(game.hands["p1"])

      assert {:error, :trick_complete} =
        Briskula.Game.play_card(game, "p1", card)
    end

    test "rejects play when not player's turn" do
      game = Fixtures.game_1v1(
        current_player: "p1",
        turn_order: ["p1", "p2"]
      )
      card = hd(game.hands["p2"])

      assert {:error, :not_players_turn} =
        Briskula.Game.play_card(game, "p2", card)
    end

    test "rejects card not in player's hand" do
      game = Fixtures.game_1v1()
      # Use a card that p1 doesn't have
      invalid_card = Fixtures.card(:coins, :king)

      assert {:error, :card_not_in_hand} =
        Briskula.Game.play_card(game, "p1", invalid_card)
    end
  end

  # ========================================
  # Tests for Briskula.Game.resolve_trick/1
  # ========================================

  describe "Game.resolve_trick/1 - winner determination -->" do
    test "lead suit wins when no trump played" do
      # Trump is :cups, lead is :spades
      # p1 plays :spades:ace (lead, strongest), p2 plays :spades:king (lead, weaker)
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:spades, :king)}
      ]

      game = Fixtures.game_with_completed_trick_1v1(table, :cups)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # p1 should win with the stronger lead suit card
      assert updated_game.current_player == "p1"
      assert length(updated_game.captured_cards["p1"]) == 2
      assert length(updated_game.captured_cards["p2"]) == 0
    end

    test "trump beats lead suit (even weak trump)" do
      # Trump is :cups, lead is :spades
      # p1 plays :spades:ace (lead, normally strong), p2 plays :cups:2 (trump, weakest)
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:cups, :"2")}
      ]

      game = Fixtures.game_with_completed_trick_1v1(table, :cups)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # p2 should win with trump, even though it's the weakest trump
      assert updated_game.current_player == "p2"
      assert length(updated_game.captured_cards["p2"]) == 2
      assert length(updated_game.captured_cards["p1"]) == 0
    end

    test "highest trump wins when multiple trumps played" do
      # Trump is :cups, lead is :spades
      # Multiple trumps played, highest trump should win
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:cups, :"7")},
        {"p3", Fixtures.card(:cups, :ace)},
        {"p4", Fixtures.card(:cups, :three)}
      ]

      game = Fixtures.game_with_completed_trick_2v2(table, :cups)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # p3 should win with :cups:ace (strongest trump)
      assert updated_game.current_player == "p3"
      assert length(updated_game.captured_cards["p3"]) == 4
    end

    test "non-lead non-trump cards are ignored" do
      # Trump is :cups, lead is :spades
      # p1 plays :spades:king (lead), p2 plays :coins:ace (not lead, not trump)
      table = [
        {"p1", Fixtures.card(:spades, :king)},
        {"p2", Fixtures.card(:coins, :ace)}
      ]

      game = Fixtures.game_with_completed_trick_1v1(table, :cups)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # p1 should win (only card in lead suit)
      assert updated_game.current_player == "p1"
      assert length(updated_game.captured_cards["p1"]) == 2
    end
  end

  describe "Game.resolve_trick/1 - happy path (1v1) -->" do
    test "trick resolution - game continues" do
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:spades, :king)}
      ]

      # Deck with 4 cards, hands with 1 card each
      game = Fixtures.game_with_completed_trick_1v1(table, :cups)
      initial_deck_size = length(game.deck)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # Winner captured cards
      assert length(updated_game.captured_cards["p1"]) == 2

      # Table reset
      assert updated_game.table == []

      # Turn order rotated with winner first
      assert updated_game.turn_order == ["p1", "p2"]
      assert updated_game.current_player == "p1"

      # Each player dealt 1 card
      assert length(updated_game.hands["p1"]) == 2
      assert length(updated_game.hands["p2"]) == 2

      # Deck decreased by 2
      assert length(updated_game.deck) == initial_deck_size - 2
    end

    test "last trick - game completes" do
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:spades, :king)}
      ]

      # Empty deck and hands
      game = Fixtures.game_last_trick_1v1(table, :cups)

      assert {:game_complete, updated_game} = Briskula.Game.resolve_trick(game)

      # Game phase changed to finished
      assert updated_game.phase == :finished

      # Winner captured cards
      assert length(updated_game.captured_cards["p1"]) == 2

      # Table reset
      assert updated_game.table == []

      # No cards dealt (deck empty)
      assert updated_game.hands["p1"] == []
      assert updated_game.hands["p2"] == []
      assert updated_game.deck == []
    end
  end

  describe "Game.resolve_trick/1 - happy path (2v2) -->" do
    test "trick resolution - game continues" do
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:spades, :king)},
        {"p3", Fixtures.card(:spades, :three)},
        {"p4", Fixtures.card(:spades, :knight)}
      ]

      # Deck with 4 cards, hands with 1 card each
      game = Fixtures.game_with_completed_trick_2v2(table, :cups)
      initial_deck_size = length(game.deck)

      assert {:continue, updated_game} = Briskula.Game.resolve_trick(game)

      # Winner (p1) captured all 4 cards
      assert length(updated_game.captured_cards["p1"]) == 4

      # Table reset
      assert updated_game.table == []

      # Turn order rotated with winner first
      assert updated_game.turn_order == ["p1", "p2", "p3", "p4"]
      assert updated_game.current_player == "p1"

      # Each of 4 players dealt 1 card
      assert length(updated_game.hands["p1"]) == 2
      assert length(updated_game.hands["p2"]) == 2
      assert length(updated_game.hands["p3"]) == 2
      assert length(updated_game.hands["p4"]) == 2

      # Deck decreased by 4
      assert length(updated_game.deck) == initial_deck_size - 4
    end

    test "last trick - game completes" do
      table = [
        {"p1", Fixtures.card(:spades, :ace)},
        {"p2", Fixtures.card(:spades, :king)},
        {"p3", Fixtures.card(:spades, :three)},
        {"p4", Fixtures.card(:spades, :knight)}
      ]

      # Empty deck and hands
      game = Fixtures.game_last_trick_2v2(table, :cups)

      assert {:game_complete, updated_game} = Briskula.Game.resolve_trick(game)

      # Game phase changed to finished
      assert updated_game.phase == :finished

      # Winner (p1) captured all 4 cards
      assert length(updated_game.captured_cards["p1"]) == 4

      # Table reset
      assert updated_game.table == []

      # No cards dealt (deck empty)
      assert updated_game.hands["p1"] == []
      assert updated_game.hands["p2"] == []
      assert updated_game.hands["p3"] == []
      assert updated_game.hands["p4"] == []
      assert updated_game.deck == []
    end
  end

  describe "Game.resolve_trick/1 - unhappy path -->" do
    test "rejects resolution when trick not complete" do
      game = Fixtures.game_1v1(
        turn_order: [:p2],
        current_player: :p2
      )

      assert {:error, :trick_not_complete} = Briskula.Game.resolve_trick(game)
    end
  end

  # ========================================
  # Tests for Briskula.Game.finalize_game/1
  # ========================================

  describe "Game.finalize_game/1 - happy path (1v1) -->" do
    test "returns scores when game complete" do
      # p1 captured: ace (11) + king (4) = 15
      # p2 captured: three (10) + knave (2) = 12
      game = Fixtures.game_1v1(
      deck: [],
        hands: %{"p1" => [], "p2" => []},
        captured_cards: %{
        "p1" => [
            Fixtures.card(:spades, :ace),
            Fixtures.card(:cups, :king)
        ],
        "p2" => [
            Fixtures.card(:batons, :three),
            Fixtures.card(:coins, :knave)
          ]
        }
      )

      assert {:game_over, returned_game, scores} = Briskula.Game.finalize_game(game)

      # Verify correct tuple structure
      assert returned_game == game

      # Verify scoring calculation
      assert scores["p1"] == 15
      assert scores["p2"] == 12
    end
  end

  describe "Game.finalize_game/1 - happy path (2v2) -->" do
    test "returns team scores when game complete" do
      # team1 (p1 + p3): ace (11) + king (4) + three (10) = 25
      # team2 (p2 + p4): knight (3) + knave (2) = 5
      game = Fixtures.game_2v2(
        deck: [],
        hands: %{"p1" => [], "p2" => [], "p3" => [], "p4" => []},
        captured_cards: %{
          "p1" => [Fixtures.card(:spades, :ace)],
          "p2" => [Fixtures.card(:coins, :knight)],
          "p3" => [
            Fixtures.card(:cups, :king),
            Fixtures.card(:batons, :three)
          ],
          "p4" => [Fixtures.card(:spades, :knave)]
        }
      )

      assert {:game_over, returned_game, scores} = Briskula.Game.finalize_game(game)

      # Verify correct tuple structure
      assert returned_game == game

      # Verify team aggregation
      assert Map.keys(scores) == [:team1, :team2]
      assert scores[:team1] == 25
      assert scores[:team2] == 5
    end
  end

  describe "Game.finalize_game/1 - unhappy path -->" do
    test "rejects when deck not empty" do
      game = Fixtures.game_1v1(
        deck: [Fixtures.card(:coins, :ace)],
        hands: %{"p1" => [], "p2" => []}
      )

      assert {:error, :game_not_complete} = Briskula.Game.finalize_game(game)
    end

    test "rejects when hands not empty" do
      game = Fixtures.game_1v1(
        deck: [],
        hands: %{
          "p1" => [Fixtures.card(:spades, :king)],
          "p2" => []
        }
      )

      assert {:error, :game_not_complete} = Briskula.Game.finalize_game(game)
    end
  end

  # ========================================
  # Tests for Briskula.Game.filter_view/2
  # ========================================

  describe "Game.filter_view/2 - happy path (1v1) -->" do
    test "filters view correctly for requesting player" do
      p1_cards = [
        Fixtures.card(:spades, :ace),
        Fixtures.card(:cups, :king)
      ]
      p2_cards = [
        Fixtures.card(:batons, :three),
        Fixtures.card(:coins, :knave)
      ]

      game = Fixtures.game_1v1(
        hands: %{"p1" => p1_cards, "p2" => p2_cards},
        deck: [
          Fixtures.card(:coins, :"7"),
          Fixtures.card(:batons, :"6")
        ],
        captured_cards: %{
          "p1" => [Fixtures.card(:spades, :knight)],
          "p2" => [Fixtures.card(:cups, :"5"), Fixtures.card(:batons, :"4")]
        },
        table: [{"p1", Fixtures.card(:coins, :ace)}],
        trump_card: Fixtures.card(:cups, :three)
      )

      view = Briskula.Game.filter_view(game, "p1")

      # Player sees their own full hand
      assert view.hand == p1_cards

      # Other players' hands are hidden (only counts shown)
      assert view.hand_counts == %{"p1" => 2, "p2" => 2}

      # Deck count only (not actual cards)
      assert view.deck_count == 2

      # Captured cards are counts only
      assert view.captured_card_counts == %{"p1" => 1, "p2" => 2}

      # Public info is visible
      assert view.phase == :playing
      assert view.players == ["p1", "p2"]
      assert view.teams == nil
      assert view.trump_card == Fixtures.card(:cups, :three)
      assert view.table == [{"p1", Fixtures.card(:coins, :ace)}]
      assert view.turn_order == ["p1", "p2"]
      assert view.current_player == "p1"
    end
  end

  describe "Game.filter_view/2 - happy path (2v2) -->" do
    test "filters view correctly for requesting player in team game" do
      p1_cards = [Fixtures.card(:spades, :ace)]
      p2_cards = [Fixtures.card(:cups, :king)]
      p3_cards = [Fixtures.card(:batons, :three)]
      p4_cards = [Fixtures.card(:coins, :knave)]

      game = Fixtures.game_2v2(
        hands: %{"p1" => p1_cards, "p2" => p2_cards, "p3" => p3_cards, "p4" => p4_cards},
        deck: [Fixtures.card(:coins, :"7")],
        captured_cards: %{
          "p1" => [Fixtures.card(:spades, :knight)],
          "p2" => [],
          "p3" => [Fixtures.card(:cups, :"5")],
          "p4" => [Fixtures.card(:batons, :"4")]
        }
      )

      view = Briskula.Game.filter_view(game, "p3")

      # p3 sees their own full hand
      assert view.hand == p3_cards

      # All players' hand counts are visible (but not cards)
      assert view.hand_counts == %{"p1" => 1, "p2" => 1, "p3" => 1, "p4" => 1}

      # Deck count only
      assert view.deck_count == 1

      # Captured card counts
      assert view.captured_card_counts == %{"p1" => 1, "p2" => 0, "p3" => 1, "p4" => 1}

      # Public info including teams
      assert view.phase == :playing
      assert view.players == ["p1", "p2", "p3", "p4"]
      assert view.teams == %{team1: ["p1", "p3"], team2: ["p2", "p4"]}
      assert view.current_player == "p1"
    end
  end
end
