from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


def _natural_key(value: str) -> tuple[int, int | str]:
    text = str(value)
    return (0, int(text)) if text.isdigit() else (1, text)


@dataclass(slots=True)
class IndexMappings:
    user_to_index: dict[str, int]
    item_to_index: dict[str, int]

    @property
    def index_to_user(self) -> list[str]:
        result = [""] * len(self.user_to_index)
        for value, index in self.user_to_index.items():
            result[index] = value
        return result

    @property
    def index_to_item(self) -> list[str]:
        result = [""] * len(self.item_to_index)
        for value, index in self.item_to_index.items():
            result[index] = value
        return result


def build_mappings(
    interactions: pd.DataFrame,
    *,
    item_ids: list[str] | None = None,
) -> IndexMappings:
    users = sorted({str(value) for value in interactions["user_id"]}, key=_natural_key)
    items = (
        sorted({str(value) for value in item_ids}, key=_natural_key)
        if item_ids is not None
        else sorted({str(value) for value in interactions["item_id"]}, key=_natural_key)
    )
    return IndexMappings(
        user_to_index={value: index for index, value in enumerate(users)},
        item_to_index={value: index for index, value in enumerate(items)},
    )


def encode_interactions(
    interactions: pd.DataFrame,
    mappings: IndexMappings,
) -> pd.DataFrame:
    encoded = interactions.copy()
    encoded["user_index"] = encoded["user_id"].map(mappings.user_to_index)
    encoded["item_index"] = encoded["item_id"].map(mappings.item_to_index)
    if encoded[["user_index", "item_index"]].isna().any().any():
        raise ValueError("Interaction contains an ID that is missing from index mappings.")
    encoded["user_index"] = encoded["user_index"].astype("int64")
    encoded["item_index"] = encoded["item_index"].astype("int64")
    return encoded


def build_seen_csr(
    interactions: pd.DataFrame,
    mappings: IndexMappings,
) -> tuple[np.ndarray, np.ndarray]:
    encoded = encode_interactions(interactions, mappings)
    grouped = {
        int(user): sorted({int(item) for item in values})
        for user, values in encoded.groupby("user_index")["item_index"]
    }
    indptr = [0]
    indices: list[int] = []
    for user_index in range(len(mappings.user_to_index)):
        indices.extend(grouped.get(user_index, []))
        indptr.append(len(indices))
    return np.asarray(indptr, dtype=np.int64), np.asarray(indices, dtype=np.int64)


def save_seen_csr(
    path: str | Path,
    indptr: np.ndarray,
    indices: np.ndarray,
) -> None:
    np.savez_compressed(path, indptr=indptr, indices=indices)
