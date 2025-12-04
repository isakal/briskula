defmodule Briskula.FilteredGameView do
  @moduledoc "Represents a player-specific view of the game state."

  alias Briskula.Card

  defstruct [
    :phase,
    :players,
    :teams,
    :deck_count,
    :trump_card,
    :hand,
    :hand_counts,
    :captured_card_counts,
    :table,
    :turn_order,
    :current_player,
  ]

  @type t :: %__MODULE__{
          phase: atom,
          players: [atom],
          teams: [atom] | nil,
          trump_card: Card.t(),
          table: [Card.t()],
          turn_order: [atom],
          current_player: atom,
          deck_count: non_neg_integer(),
          hand: [Card.t()],
          hand_counts: %{atom => non_neg_integer()},
          captured_card_counts: %{atom => non_neg_integer()}
        }
end
