from __future__ import annotations

from training.cohorts import temporal_train_test_split


def test_temporal_split_keeps_latest_interaction_for_test(
    synthetic_interactions,
) -> None:
    train, test = temporal_train_test_split(synthetic_interactions)

    assert len(train) == 8
    assert len(test) == 4
    assert train.groupby("user_index").size().to_dict() == {
        0: 2,
        1: 2,
        2: 2,
        3: 2,
    }
    assert test.groupby("user_index").size().to_dict() == {
        0: 1,
        1: 1,
        2: 1,
        3: 1,
    }
    for user_index, user_test in test.groupby("user_index"):
        user_train = train[train["user_index"] == user_index]
        assert user_test["timestamp"].min() > user_train["timestamp"].max()
