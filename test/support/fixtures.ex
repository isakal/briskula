defmodule Briskula.Fixtures do
  @moduledoc """
  Test fixtures for creating game states with sensible defaults.
  """

  @doc "Creates a 1v1 game with default or custom options"
  def game_1v1(opts \\ []) do
    %Briskula.Game{
      phase: Keyword.get(opts, :phase, :playing),
      players: Keyword.get(opts, :players, ["p1", "p2"]),
      teams: nil,
      deck: Keyword.get(opts, :deck, []),
      trump_card: Keyword.get(opts, :trump_card, card(:cups, :ace)),
      hands: Keyword.get(opts, :hands, default_1v1_hands()),
      captured_cards: Keyword.get(opts, :captured_cards, %{"p1" => [], "p2" => []}),
      table: Keyword.get(opts, :table, []),
      turn_order: Keyword.get(opts, :turn_order, ["p1", "p2"]),
      current_player: Keyword.get(opts, :current_player, "p1")
    }
  end

  @doc "Creates a 2v2 game with default or custom options"
  def game_2v2(opts \\ []) do
    %Briskula.Game{
      phase: Keyword.get(opts, :phase, :playing),
      players: Keyword.get(opts, :players, ["p1", "p2", "p3", "p4"]),
      teams: Keyword.get(opts, :teams, %{team1: ["p1", "p3"], team2: ["p2", "p4"]}),
      deck: Keyword.get(opts, :deck, []),
      trump_card: Keyword.get(opts, :trump_card, card(:cups, :ace)),
      hands: Keyword.get(opts, :hands, default_2v2_hands()),
      captured_cards: Keyword.get(opts, :captured_cards, %{"p1" => [], "p2" => [], "p3" => [], "p4" => []}),
      table: Keyword.get(opts, :table, []),
      turn_order: Keyword.get(opts, :turn_order, ["p1", "p2", "p3", "p4"]),
      current_player: Keyword.get(opts, :current_player, "p1")
    }
  end

  @doc "Helper to create a card"
  def card(suit, rank) do
    %Briskula.Card{suit: suit, rank: rank}
  end

  @doc "Creates a 1v1 game with a completed trick ready to resolve"
  def game_with_completed_trick_1v1(table_cards, trump_suit, opts \\ []) do
    game_1v1(
      Keyword.merge(
        [
          trump_card: card(trump_suit, :ace),
          table: table_cards,
          turn_order: [],
          current_player: nil,
          deck: Keyword.get(opts, :deck, default_deck()),
          hands: Keyword.get(opts, :hands, %{"p1" => [card(:coins, :king)], "p2" => [card(:batons, :king)]})
        ],
        opts
      )
    )
  end

  @doc "Creates a 2v2 game with a completed trick ready to resolve"
  def game_with_completed_trick_2v2(table_cards, trump_suit, opts \\ []) do
    game_2v2(
      Keyword.merge(
        [
          trump_card: card(trump_suit, :ace),
          table: table_cards,
          turn_order: [],
          current_player: nil,
          deck: Keyword.get(opts, :deck, default_deck()),
          hands:
            Keyword.get(opts, :hands, %{
              "p1" => [card(:coins, :king)],
              "p2" => [card(:batons, :king)],
              "p3" => [card(:coins, :knave)],
              "p4" => [card(:batons, :knave)]
            })
        ],
        opts
      )
    )
  end

  @doc "Creates a 1v1 game at the last trick (empty deck and hands)"
  def game_last_trick_1v1(table_cards, trump_suit) do
    game_1v1(
      trump_card: card(trump_suit, :ace),
      table: table_cards,
      turn_order: [],
      current_player: nil,
      deck: [],
      hands: %{"p1" => [], "p2" => []}
    )
  end

  @doc "Creates a 2v2 game at the last trick (empty deck and hands)"
  def game_last_trick_2v2(table_cards, trump_suit) do
    game_2v2(
      trump_card: card(trump_suit, :ace),
      table: table_cards,
      turn_order: [],
      current_player: nil,
      deck: [],
      hands: %{"p1" => [], "p2" => [], "p3" => [], "p4" => []}
    )
  end

  defp default_deck do
    [
      card(:coins, :"7"),
      card(:coins, :"6"),
      card(:batons, :"5"),
      card(:spades, :"4")
    ]
  end

  defp default_1v1_hands do
    %{
      "p1" => [
        card(:batons, :three),
        card(:spades, :knight),
        card(:spades, :ace)
      ],
      "p2" => [
        card(:cups, :"7"),
        card(:cups, :"6"),
        card(:spades, :king)
      ]
    }
  end

  defp default_2v2_hands do
    %{
      "p1" => [
        card(:batons, :three),
        card(:spades, :knight),
        card(:spades, :ace)
      ],
      "p2" => [
        card(:cups, :"7"),
        card(:cups, :"6"),
        card(:spades, :king)
      ],
      "p3" => [
        card(:coins, :three),
        card(:coins, :knight),
        card(:batons, :ace)
      ],
      "p4" => [
        card(:batons, :"7"),
        card(:batons, :"6"),
        card(:coins, :king)
      ]
    }
  end
end
