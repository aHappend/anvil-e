"""Frozen representative dispatch cells; not a Cartesian-coverage claim."""

from dataclasses import dataclass


SEEDS = (17, 43, 89)
CAPACITIES = (1, 3, 64)


@dataclass(frozen=True)
class TopCell:
    model: int
    precision: int
    seed: int
    capacity: int
    tokens: int
    fallback: int

    @property
    def fixture_key(self):
        return self.model, self.precision, self.seed, self.tokens

    @property
    def key(self):
        return (self.model, self.precision, self.seed, self.capacity,
                self.tokens, self.fallback)


def top_cells():
    cells = []
    for model in (1, 2):
        for precision in (0, 1):
            offset = 2 * (model - 1) + precision
            for index, tokens in enumerate((1, 16, 17)):
                cells.append(TopCell(model, precision, SEEDS[(offset + index) % 3],
                                     CAPACITIES[(offset + index) % 3], tokens, 0))
            for index, tokens in enumerate((1, 17), 1):
                cells.append(TopCell(model, precision, SEEDS[(offset + index + 1) % 3],
                                     CAPACITIES[(offset + index) % 3], tokens, 1))
    return tuple(cells)


def fixture_keys():
    return tuple(dict.fromkeys(cell.fixture_key for cell in top_cells()))


def batch_cells(capacity, fallback, models=(1, 2), precisions=(0, 1),
                seeds=SEEDS, contexts=(1, 16, 17)):
    return tuple(cell for cell in top_cells()
                 if cell.capacity == capacity and cell.fallback == int(fallback) and
                 cell.model in models and cell.precision in precisions and
                 cell.seed in seeds and cell.tokens in contexts)
