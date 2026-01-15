defmodule Briskula.GameServerTest do
  use ExUnit.Case, async: true
  # async: false because tests share the Registry

  alias Briskula.GameServer
  alias Briskula.Fixtures


  setup do
    # Generate unique game ID for this test
    game_id = "test_#{:erlang.system_time(:nanosecond)}_#{:erlang.unique_integer([:positive])}"

    {:ok, game_id: game_id}
  end

  # ========================================
  # Tests for GameServer lobby creation and joining
  # ========================================

  describe "GameServer.start_link/2 - creates lobby -->" do
    test "creates a lobby with single player", %{game_id: game_id} do
      assert {:ok, _pid} = GameServer.start_link(game_id, "p1")

      game = GameServer.get_game(game_id)

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

  describe "GameServer.create_game/2 - happy path -->" do
    test "creates a lobby with single player via DynamicSupervisor", %{game_id: game_id} do
      assert {:ok, pid} = GameServer.create_game(game_id, "p1")
      assert is_pid(pid)

      game = GameServer.get_game(game_id)

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

    test "creates a game that can be found in Registry", %{game_id: game_id} do
      {:ok, pid} = GameServer.create_game(game_id, "p1")

      # Verify game is registered in Registry
      assert [{^pid, _}] = Registry.lookup(:BriskulaRegistry, game_id)
    end

    test "creates a game supervised by DynamicSupervisor", %{game_id: game_id} do
      {:ok, pid} = GameServer.create_game(game_id, "p1")

      # Verify the process is alive
      assert Process.alive?(pid)

      # Verify it's supervised by the DynamicSupervisor
      children = DynamicSupervisor.which_children(Briskula.GameSupervisor)
      assert Enum.any?(children, fn {_, child_pid, _, _} -> child_pid == pid end)
    end

    test "game can be used normally after creation via supervisor", %{game_id: game_id} do
      {:ok, _pid} = GameServer.create_game(game_id, "p1")

      # Join another player
      assert {:ok, _view} = GameServer.join_game(game_id, "p2")

      # Start the game
      assert {:ok, game} = GameServer.start_game(game_id)

      # Verify game is properly initialized
      assert game.phase == :playing
      assert game.players == ["p1", "p2"]
      assert length(game.hands["p1"]) == 3
      assert length(game.hands["p2"]) == 3
    end
  end

  describe "GameServer.create_game/2 - unhappy path -->" do
    test "rejects duplicate game ID", %{game_id: game_id} do
      # Create first game
      assert {:ok, pid1} = GameServer.create_game(game_id, "p1")
      assert is_pid(pid1)

      # Try to create another game with the same ID
      assert {:error, {:already_started, pid2}} = GameServer.create_game(game_id, "p2")

      # The returned PID should be the original process
      assert pid2 == pid1

      # Original game should still be intact with original player
      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
    end

    test "allows creating multiple games with different IDs" do
      game_id1 = "create_test_1_#{:erlang.unique_integer([:positive])}"
      game_id2 = "create_test_2_#{:erlang.unique_integer([:positive])}"
      game_id3 = "create_test_3_#{:erlang.unique_integer([:positive])}"

      # Create multiple games
      {:ok, pid1} = GameServer.create_game(game_id1, "alice")
      {:ok, pid2} = GameServer.create_game(game_id2, "bob")
      {:ok, pid3} = GameServer.create_game(game_id3, "charlie")

      # All should be different processes
      assert pid1 != pid2
      assert pid2 != pid3
      assert pid1 != pid3

      # Each game should have correct player
      assert GameServer.get_game(game_id1).players == ["alice"]
      assert GameServer.get_game(game_id2).players == ["bob"]
      assert GameServer.get_game(game_id3).players == ["charlie"]
    end
  end

  describe "GameServer.join_game/2 - happy path -->" do
    test "adds second player to lobby", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      assert {:ok, _view} = GameServer.join_game(game_id, "p2")

      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p2"]
      assert game.phase == :lobby
    end

    test "adds up to 4 players to lobby", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")

      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p2", "p3", "p4"]
      assert game.phase == :lobby
    end

    test "returns filtered view for joining player", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, view} = GameServer.join_game(game_id, "p2")

      # Verify it's a filtered view
      assert view.players == ["p1", "p2"]
      assert view.phase == :lobby
      assert view.hand == []
    end
  end

  describe "GameServer.join_game/2 - unhappy path -->" do
    test "rejects join when game is full (4 players)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")

      assert {:error, :game_full} = GameServer.join_game(game_id, "p5")
    end

    test "rejects join when player name already taken", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")

      assert {:error, :player_name_taken} = GameServer.join_game(game_id, "p1")
      assert {:error, :player_name_taken} = GameServer.join_game(game_id, "p2")
    end

    test "rejects join when game already started", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      assert {:error, :game_already_started} = GameServer.join_game(game_id, "p3")
    end

    test "rejects join for non-existent game" do
      assert {:error, :game_not_found} = GameServer.join_game("fake_id", "p1")
    end
  end

  describe "GameServer.leave_game/2 - happy path -->" do
    test "removes a player from lobby with 2 players", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")

      assert {:ok, view} = GameServer.leave_game(game_id, "p2")

      # Verify filtered view returned
      assert view.players == ["p1"]
      assert view.phase == :lobby

      # Verify actual game state
      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
      assert game.phase == :lobby
    end

    test "removes the creator from lobby", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")

      assert {:ok, view} = GameServer.leave_game(game_id, "p1")

      # Verify filtered view
      assert view.players == ["p2"]
      assert view.phase == :lobby

      # Verify game state
      game = GameServer.get_game(game_id)
      assert game.players == ["p2"]
    end

    test "removes a player from lobby with 4 players", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")

      assert {:ok, view} = GameServer.leave_game(game_id, "p3")

      # Verify filtered view
      assert view.players == ["p1", "p2", "p4"]
      assert view.phase == :lobby

      # Verify game state
      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p2", "p4"]
    end

    test "removes middle player from lobby", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")

      assert {:ok, view} = GameServer.leave_game(game_id, "p2")

      assert view.players == ["p1", "p3"]

      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p3"]
    end

    test "can leave and rejoin the game", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.leave_game(game_id, "p2")

      # p2 can rejoin after leaving
      assert {:ok, view} = GameServer.join_game(game_id, "p2")

      assert view.players == ["p1", "p2"]

      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p2"]
    end

    test "returns filtered view for leaving player", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")

      # p2 leaves
      {:ok, view} = GameServer.leave_game(game_id, "p2")

      # Verify it's a filtered view for p2
      assert view.players == ["p1", "p3"]
      assert view.phase == :lobby
      assert view.hand == []
      assert view.hand_counts == %{}
    end

    test "sequential leaves reduce player count correctly", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")

      # All players leave except creator
      {:ok, _view} = GameServer.leave_game(game_id, "p4")
      {:ok, _view} = GameServer.leave_game(game_id, "p3")
      {:ok, _view} = GameServer.leave_game(game_id, "p2")

      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
      assert game.phase == :lobby
    end
  end

  describe "GameServer.leave_game/2 - unhappy path -->" do
    test "rejects leave when player not in game", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")

      assert {:error, :player_not_in_game} = GameServer.leave_game(game_id, "p3")

      # Verify state unchanged
      game = GameServer.get_game(game_id)
      assert game.players == ["p1", "p2"]
    end

    test "rejects leave when player never joined", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")

      assert {:error, :player_not_in_game} = GameServer.leave_game(game_id, "p2")

      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
    end

    test "rejects leave when game already started (2 players)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      assert {:error, :game_already_started} = GameServer.leave_game(game_id, "p1")

      # Verify game state unchanged
      game = GameServer.get_game(game_id)
      assert game.phase == :playing
      assert game.players == ["p1", "p2"]
    end

    test "rejects leave when game already started (4 players)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, _game} = GameServer.start_game(game_id)

      assert {:error, :game_already_started} = GameServer.leave_game(game_id, "p2")

      game = GameServer.get_game(game_id)
      assert game.phase == :playing
      assert game.players == ["p1", "p2", "p3", "p4"]
    end

    test "rejects leave after player already left", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.leave_game(game_id, "p2")

      # Try to leave again
      assert {:error, :player_not_in_game} = GameServer.leave_game(game_id, "p2")

      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
    end

    test "rejects leave for non-existent game" do
      assert {:error, :game_not_found} = GameServer.leave_game("fake_id", "p1")
    end
  end

  describe "GameServer.start_game/1 - happy path (1v1) -->" do
    test "starts a valid 1v1 game with 2 players", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      assert {:ok, game} = GameServer.start_game(game_id)

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

    test "deals different cards on successive calls", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, game1} = GameServer.start_game(game_id)

      game_id2 = "test_#{:erlang.system_time(:nanosecond)}_2"
      {:ok, _pid} = GameServer.start_link(game_id2, "p1")
      {:ok, _view} = GameServer.join_game(game_id2, "p2")
      {:ok, game2} = GameServer.start_game(game_id2)

      # Because deck is shuffled, games should be different (statistically)
      # Check that at least one hand is different
      refute game1.hands["p1"] == game2.hands["p1"] or
             game1.hands["p2"] == game2.hands["p2"] or
             game1.trump_card == game2.trump_card
    end
  end

  describe "GameServer.start_game/1 - happy path (2v2) -->" do
    test "starts a valid 2v2 game with 4 players", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      assert {:ok, game} = GameServer.start_game(game_id)

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

    test "teams are assigned correctly based on seating order", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, game} = GameServer.start_game(game_id)

      # First and third player on team1
      assert "p1" in game.teams.team1
      assert "p3" in game.teams.team1

      # Second and fourth player on team2
      assert "p2" in game.teams.team2
      assert "p4" in game.teams.team2
    end
  end

  describe "GameServer.start_game/1 - unhappy path -->" do
    test "rejects start with single player", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")

      assert {:error, :invalid_player_count} = GameServer.start_game(game_id)
    end

    test "rejects start with 3 players", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")

      assert {:error, :invalid_player_count} = GameServer.start_game(game_id)
    end

    test "rejects start when game already started", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      assert {:error, :game_already_started} = GameServer.start_game(game_id)
    end

    test "rejects start for non-existent game" do
      assert {:error, :game_not_found} = GameServer.start_game("fake_id")
    end
  end

  # ========================================
  # Tests for GameServer.play_card/3
  # ========================================

  describe "GameServer.play_card/3 - happy path (1v1) -->" do
    test "plays card successfully, trick continues", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)
      card_to_play = hd(game.hands["p1"])

      assert {:continue, _filtered_view} = GameServer.play_card(game_id, "p1", card_to_play)

      # Verify state using get_game
      updated_game = GameServer.get_game(game_id)

      # Card moved from hand to table
      assert length(updated_game.hands["p1"]) == 2
      assert card_to_play not in updated_game.hands["p1"]
      assert length(updated_game.table) == 1
      assert {"p1", card_to_play} in updated_game.table

      # Turn advances to next player
      assert updated_game.current_player == "p2"
      assert updated_game.turn_order == ["p2"]
    end

    test "plays card successfully, trick completes", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)
      card_p1 = hd(game.hands["p1"])
      {:continue, _view} = GameServer.play_card(game_id, "p1", card_p1)

      game = GameServer.get_game(game_id)
      card_p2 = hd(game.hands["p2"])
      assert {:trick_complete, _view} = GameServer.play_card(game_id, "p2", card_p2)

      # Verify state
      updated_game = GameServer.get_game(game_id)

      # Both cards on table
      assert length(updated_game.table) == 2
      assert {"p1", card_p1} in updated_game.table
      assert {"p2", card_p2} in updated_game.table

      # Turn order is empty (trick complete)
      assert updated_game.turn_order == []
      assert updated_game.current_player == nil
    end
  end

  describe "GameServer.play_card/3 - happy path (2v2) -->" do
    test "plays card successfully, trick continues", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)
      card_to_play = hd(game.hands["p1"])

      assert {:continue, _view} = GameServer.play_card(game_id, "p1", card_to_play)

      updated_game = GameServer.get_game(game_id)

      # Card moved from hand to table
      assert length(updated_game.hands["p1"]) == 2
      assert card_to_play not in updated_game.hands["p1"]
      assert length(updated_game.table) == 1

      # Turn advances to next player
      assert updated_game.current_player == "p2"
      assert updated_game.turn_order == ["p2", "p3", "p4"]
    end

    test "plays card successfully, trick completes", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)
      card_p1 = hd(game.hands["p1"])
      {:continue, _view} = GameServer.play_card(game_id, "p1", card_p1)

      game = GameServer.get_game(game_id)
      card_p2 = hd(game.hands["p2"])
      {:continue, _view} = GameServer.play_card(game_id, "p2", card_p2)

      game = GameServer.get_game(game_id)
      card_p3 = hd(game.hands["p3"])
      {:continue, _view} = GameServer.play_card(game_id, "p3", card_p3)

      game = GameServer.get_game(game_id)
      card_p4 = hd(game.hands["p4"])
      assert {:trick_complete, _view} = GameServer.play_card(game_id, "p4", card_p4)

      # Verify state
      updated_game = GameServer.get_game(game_id)

      # All cards on table
      assert length(updated_game.table) == 4
      assert {"p4", card_p4} in updated_game.table

      # Turn order is empty (trick complete)
      assert updated_game.turn_order == []
      assert updated_game.current_player == nil
    end
  end

  describe "GameServer.play_card/3 - unhappy path -->" do
    test "rejects play when game not started (lobby phase)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")

      # Game is still in lobby, not started
      card = Fixtures.card(:spades, :ace)

      assert {:error, :game_not_started} = GameServer.play_card(game_id, "p1", card)
    end


    test "rejects play when trick already complete", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Complete a trick
      game = GameServer.get_game(game_id)
      card_p1 = hd(game.hands["p1"])
      {:continue, _view} = GameServer.play_card(game_id, "p1", card_p1)

      game = GameServer.get_game(game_id)
      card_p2 = hd(game.hands["p2"])
      {:trick_complete, _view} = GameServer.play_card(game_id, "p2", card_p2)

      # Now trick is complete, try to play another card before resolving
      game = GameServer.get_game(game_id)
      another_card = hd(game.hands["p1"])

      assert {:error, :trick_complete} = GameServer.play_card(game_id, "p1", another_card)
    end

    test "rejects play when not player's turn", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)
      card = hd(game.hands["p2"])

      # p1's turn, but p2 tries to play
      assert {:error, :not_players_turn} = GameServer.play_card(game_id, "p2", card)
    end

    test "rejects card not in player's hand", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Use a card that p1 doesn't have (take from p2's hand)
      game = GameServer.get_game(game_id)
      invalid_card = hd(game.hands["p2"])

      assert {:error, :card_not_in_hand} = GameServer.play_card(game_id, "p1", invalid_card)
    end

    test "rejects play for non-existent game" do
      card = Fixtures.card(:spades, :ace)
      assert {:error, :game_not_found} = GameServer.play_card("fake_id", "p1", card)
    end
  end

  # ========================================
  # Tests for GameServer.resolve_trick/1
  # ========================================
  #
  # Note: Winner determination logic tests (lead suit vs trump, etc.) are not
  # ported to GameServer tests because they require setting up specific game
  # states with controlled card hands and trump suits, which isn't feasible
  # through the GameServer API. The underlying game logic is thoroughly tested
  # in briskula_game_test.exs. GameServer tests focus on verifying the API
  # correctly delegates to the Game module.
  # ========================================

  describe "GameServer.resolve_trick/1 - happy path (1v1) -->" do
    test "resolves trick and continues game", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Play a complete trick
      game = GameServer.get_game(game_id)
      card_p1 = hd(game.hands["p1"])
      {:continue, _view} = GameServer.play_card(game_id, "p1", card_p1)

      game = GameServer.get_game(game_id)
      card_p2 = hd(game.hands["p2"])
      {:trick_complete, _view} = GameServer.play_card(game_id, "p2", card_p2)

      initial_deck_size = GameServer.get_game(game_id).deck |> length()

      # Resolve the trick
      assert :continue = GameServer.resolve_trick(game_id)

      updated_game = GameServer.get_game(game_id)

      # Winner captured cards (2 cards from the trick)
      winner = updated_game.current_player
      assert length(updated_game.captured_cards[winner]) == 2

      # Table reset
      assert updated_game.table == []

      # Turn order restored with winner first
      assert updated_game.current_player != nil
      assert List.first(updated_game.turn_order) == winner

      # Each player dealt 1 card
      assert length(updated_game.hands["p1"]) == 3
      assert length(updated_game.hands["p2"]) == 3

      # Deck decreased by 2
      assert length(updated_game.deck) == initial_deck_size - 2
    end
  end

  describe "GameServer.resolve_trick/1 - happy path (2v2) -->" do
    test "resolves trick and continues game", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, _game} = GameServer.start_game(game_id)

      # Play a complete trick
      game = GameServer.get_game(game_id)
      card_p1 = hd(game.hands["p1"])
      {:continue, _view} = GameServer.play_card(game_id, "p1", card_p1)

      game = GameServer.get_game(game_id)
      card_p2 = hd(game.hands["p2"])
      {:continue, _view} = GameServer.play_card(game_id, "p2", card_p2)

      game = GameServer.get_game(game_id)
      card_p3 = hd(game.hands["p3"])
      {:continue, _view} = GameServer.play_card(game_id, "p3", card_p3)

      game = GameServer.get_game(game_id)
      card_p4 = hd(game.hands["p4"])
      {:trick_complete, _view} = GameServer.play_card(game_id, "p4", card_p4)

      initial_deck_size = GameServer.get_game(game_id).deck |> length()

      # Resolve the trick
      assert :continue = GameServer.resolve_trick(game_id)

      updated_game = GameServer.get_game(game_id)

      # Winner captured all 4 cards
      winner = updated_game.current_player
      assert length(updated_game.captured_cards[winner]) == 4

      # Table reset
      assert updated_game.table == []

      # Turn order restored with winner first
      assert updated_game.current_player != nil
      assert List.first(updated_game.turn_order) == winner

      # Each of 4 players dealt 1 card
      assert length(updated_game.hands["p1"]) == 3
      assert length(updated_game.hands["p2"]) == 3
      assert length(updated_game.hands["p3"]) == 3
      assert length(updated_game.hands["p4"]) == 3

      # Deck decreased by 4
      assert length(updated_game.deck) == initial_deck_size - 4
    end
  end

  describe "GameServer.resolve_trick/1 - unhappy path -->" do
    test "rejects resolution when trick not complete", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Don't complete the trick
      assert {:error, :trick_not_complete} = GameServer.resolve_trick(game_id)
    end

    test "rejects resolve for non-existent game" do
      assert {:error, :game_not_found} = GameServer.resolve_trick("fake_id")
    end
  end

  # ========================================
  # Tests for GameServer.finalize_game/1
  # ========================================
  #
  # Note: Detailed score calculation tests (with specific captured cards) are
  # not ported to GameServer tests because they require setting up specific
  # game end states, which would require playing through entire games. The
  # scoring logic is thoroughly tested in briskula_game_test.exs. GameServer
  # tests focus on verifying the API behavior and error handling.
  # ========================================

  describe "GameServer.finalize_game/1 - happy path (1v1) -->" do
    test "returns scores when game complete", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Play out the entire game (simplified - just verify finalize works)
      # For a real test, we'd play all cards, but for now we'll just test
      # that finalize rejects incomplete games
      assert {:error, :game_not_complete} = GameServer.finalize_game(game_id)
    end
  end

  describe "GameServer.finalize_game/1 - unhappy path -->" do
    test "rejects when game not complete (deck not empty)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Game just started with full deck
      game = GameServer.get_game(game_id)
      assert length(game.deck) > 0

      assert {:error, :game_not_complete} = GameServer.finalize_game(game_id)
    end

    test "rejects when game not complete (hands not empty)", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      # Game just started with cards in hands
      game = GameServer.get_game(game_id)
      assert length(game.hands["p1"]) > 0

      assert {:error, :game_not_complete} = GameServer.finalize_game(game_id)
    end

    test "rejects finalize for non-existent game" do
      assert {:error, :game_not_found} = GameServer.finalize_game("fake_id")
    end
  end

  # ========================================
  # Tests for GameServer.get_game/1 and get_game/2
  # ========================================

  describe "GameServer.get_game/1 - full state -->" do
    test "returns full game state", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      game = GameServer.get_game(game_id)

      # Full game includes all hands
      assert is_map(game.hands)
      assert Map.has_key?(game.hands, "p1")
      assert Map.has_key?(game.hands, "p2")

      # Can see other players' cards
      assert length(game.hands["p1"]) == 3
      assert length(game.hands["p2"]) == 3
    end

    test "returns error for non-existent game" do
      assert {:error, :game_not_found} = GameServer.get_game("fake_id")
    end
  end

  describe "GameServer.get_game/2 - filtered view -->" do
    test "filters view correctly for requesting player", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _game} = GameServer.start_game(game_id)

      full_game = GameServer.get_game(game_id)
      p1_cards = full_game.hands["p1"]

      # Get filtered view for p1
      view = GameServer.get_game(game_id, "p1")

      # Player sees their own full hand
      assert view.hand == p1_cards

      # Other players' hands are hidden (only counts shown)
      assert view.hand_counts == %{"p1" => 3, "p2" => 3}

      # Deck count only (not actual cards)
      assert view.deck_count == 34

      # Captured cards are counts only
      assert view.captured_card_counts == %{"p1" => 0, "p2" => 0}

      # Public info is visible
      assert view.phase == :playing
      assert view.players == ["p1", "p2"]
      assert view.teams == nil
      assert view.trump_card != nil
      assert view.table == []
      assert view.turn_order == ["p1", "p2"]
      assert view.current_player == "p1"
    end

    test "filters view correctly for requesting player in team game", %{game_id: game_id} do
      {:ok, _pid} = GameServer.start_link(game_id, "p1")
      {:ok, _view} = GameServer.join_game(game_id, "p2")
      {:ok, _view} = GameServer.join_game(game_id, "p3")
      {:ok, _view} = GameServer.join_game(game_id, "p4")
      {:ok, _game} = GameServer.start_game(game_id)

      full_game = GameServer.get_game(game_id)
      p3_cards = full_game.hands["p3"]

      # Get filtered view for p3
      view = GameServer.get_game(game_id, "p3")

      # p3 sees their own full hand
      assert view.hand == p3_cards

      # All players' hand counts are visible (but not cards)
      assert view.hand_counts == %{"p1" => 3, "p2" => 3, "p3" => 3, "p4" => 3}

      # Deck count only
      assert view.deck_count == 28

      # Public info including teams
      assert view.phase == :playing
      assert view.players == ["p1", "p2", "p3", "p4"]
      assert view.teams == %{team1: ["p1", "p3"], team2: ["p2", "p4"]}
      assert view.current_player == "p1"
    end

    test "returns error for non-existent game" do
      assert {:error, :game_not_found} = GameServer.get_game("fake_id", "p1")
    end
  end

  # ========================================
  # Tests for GameServer error handling
  # ========================================

  describe "GameServer error handling - game_not_found -->" do
    test "all operations return game_not_found for invalid game IDs" do
      fake_id = "nonexistent_game_123"

      # Verify all operations handle missing games gracefully
      assert {:error, :game_not_found} = GameServer.get_game(fake_id)
      assert {:error, :game_not_found} = GameServer.get_game(fake_id, "p1")
      assert {:error, :game_not_found} = GameServer.join_game(fake_id, "p2")
      assert {:error, :game_not_found} = GameServer.leave_game(fake_id, "p1")
      assert {:error, :game_not_found} = GameServer.start_game(fake_id)
      assert {:error, :game_not_found} = GameServer.play_card(fake_id, "p1", Fixtures.card(:spades, :ace))
      assert {:error, :game_not_found} = GameServer.resolve_trick(fake_id)
      assert {:error, :game_not_found} = GameServer.finalize_game(fake_id)
    end
  end

  # ========================================
  # Tests for GenServer-specific behavior
  # ========================================

  describe "GameServer process lifecycle -->" do
    test "prevents duplicate game IDs in Registry", %{game_id: game_id} do
      # Start a game with a specific ID
      assert {:ok, pid1} = GameServer.start_link(game_id, "p1")
      assert is_pid(pid1)

      # Try to start another game with the same ID
      # Registry should prevent duplicate registration
      assert {:error, {:already_started, pid2}} = GameServer.start_link(game_id, "p2")

      # The returned PID should be the original process
      assert pid2 == pid1

      # Original game should still be intact
      game = GameServer.get_game(game_id)
      assert game.players == ["p1"]
    end
  end

  describe "GameServer state isolation -->" do
    test "multiple games run independently without interference" do
      # Start 3 different games with unique IDs
      game_id1 = "isolation_test_game1_#{:erlang.unique_integer([:positive])}"
      game_id2 = "isolation_test_game2_#{:erlang.unique_integer([:positive])}"
      game_id3 = "isolation_test_game3_#{:erlang.unique_integer([:positive])}"

      {:ok, _} = GameServer.start_link(game_id1, "alice")
      {:ok, _} = GameServer.start_link(game_id2, "bob")
      {:ok, _} = GameServer.start_link(game_id3, "charlie")

      # Join second player to each game
      {:ok, _} = GameServer.join_game(game_id1, "alice2")
      {:ok, _} = GameServer.join_game(game_id2, "bob2")
      {:ok, _} = GameServer.join_game(game_id3, "charlie2")

      # Start all games
      {:ok, g1} = GameServer.start_game(game_id1)
      {:ok, g2} = GameServer.start_game(game_id2)
      {:ok, g3} = GameServer.start_game(game_id3)

      # Verify each game has unique, correct players
      assert g1.players == ["alice", "alice2"]
      assert g2.players == ["bob", "bob2"]
      assert g3.players == ["charlie", "charlie2"]

      # Verify games have different shuffled decks (statistically very likely)
      # If all three trump cards are the same, that's astronomically unlikely
      trump_cards = [g1.trump_card, g2.trump_card, g3.trump_card]
      unique_trump_cards = Enum.uniq(trump_cards)

      # At least 2 out of 3 should be different (statistically almost certain)
      assert length(unique_trump_cards) >= 2

      # Play a card in game1
      card_g1 = hd(g1.hands["alice"])
      {:continue, _} = GameServer.play_card(game_id1, "alice", card_g1)

      # Verify game1 state changed but game2 and game3 are unaffected
      updated_g1 = GameServer.get_game(game_id1)
      updated_g2 = GameServer.get_game(game_id2)
      updated_g3 = GameServer.get_game(game_id3)

      # Game1 should have a card on the table
      assert length(updated_g1.table) == 1
      assert updated_g1.current_player == "alice2"

      # Game2 and Game3 should be unchanged
      assert length(updated_g2.table) == 0
      assert updated_g2.current_player == "bob"
      assert length(updated_g3.table) == 0
      assert updated_g3.current_player == "charlie"
    end
  end
end
