from uuid import uuid4

import pytest

from app.config import Settings
from app.model_registry import ModelRegistry, ModelJobCancelled, ModelJobFinalizing
from test_r2_update import FakeR2


def registry_with_store(monkeypatch, tmp_path):
    store = FakeR2()
    monkeypatch.setattr('app.model_registry.R2Store', lambda _: store)
    registry = ModelRegistry(Settings(model_storage_path=tmp_path))
    return registry, store


def test_cancel_before_submission_is_durable_and_idempotent(monkeypatch, tmp_path):
    registry, store = registry_with_store(monkeypatch, tmp_path)
    job_id = str(uuid4())
    first = registry.cancel_job(job_id)
    second = registry.cancel_job(job_id)
    assert first == second and first['status'] == 'cancelled'
    assert not registry.create_job(job_id, {'jobId': job_id, 'status': 'running'})
    assert store.read_json(f'collaborative_cf/jobs/{job_id}.json')['status'] == 'cancelled'


def test_cancel_wins_publication_race_and_cannot_be_overwritten(monkeypatch, tmp_path):
    registry, store = registry_with_store(monkeypatch, tmp_path)
    job_id = str(uuid4())
    registry.create_job(job_id, {'jobId': job_id, 'status': 'running'})
    old = {'modelVersion': 'previous'}
    store.write_json('collaborative_cf/active.json', old)
    registry.cancel_job(job_id)
    with pytest.raises(ModelJobCancelled):
        registry.begin_publication(job_id)
    registry.record_job(job_id, {'jobId': job_id, 'status': 'failed'})
    assert registry.get_job(job_id)['status'] == 'cancelled'
    assert store.read_json('collaborative_cf/active.json') == old


def test_publication_winner_rejects_late_cancel_without_false_ack(monkeypatch, tmp_path):
    registry, store = registry_with_store(monkeypatch, tmp_path)
    job_id = str(uuid4())
    registry.create_job(job_id, {'jobId': job_id, 'status': 'running'})
    registry.begin_publication(job_id)
    with pytest.raises(ModelJobFinalizing):
        registry.cancel_job(job_id)
    assert store.read_json(f'collaborative_cf/jobs/{job_id}.json')['status'] == 'publishing'


def test_old_identical_manifest_does_not_complete_new_guarded_job(monkeypatch, tmp_path):
    registry, store = registry_with_store(monkeypatch, tmp_path)
    job_id = str(uuid4())
    job = {'jobId': job_id, 'status': 'running', 'csvKey': 'same.csv', 'csvSha256': 'abc',
           'modelAlgorithm': 'item_based', 'publicationGuard': True, 'scoreAggregation': {'mode': 'average'}}
    registry.create_job(job_id, job)
    store.write_json('collaborative_cf/active.json', {**job, 'jobId': str(uuid4())})
    assert registry.get_job(job_id)['status'] == 'running'
    registry.begin_publication(job_id)
