import argparse
import hashlib
import json
import os
import platform
import resource
import socket
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

cache_root = Path(".hf-cache").resolve()
os.environ.setdefault("HF_HOME", str(cache_root))
os.environ.setdefault("HF_HUB_CACHE", str(cache_root / "hub"))
joblib_root = Path(".joblib").resolve()
joblib_root.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("JOBLIB_TEMP_FOLDER", str(joblib_root))

from dotenv import load_dotenv

load_dotenv()

import numpy as np
import torch
from sentence_transformers import SentenceTransformer


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_corpus(path: Path) -> list[dict]:
    records = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            records.append(json.loads(line))
    return records


def batch_iter(items: list[str], batch_size: int):
    for idx in range(0, len(items), batch_size):
        yield idx, items[idx : idx + batch_size]


def git_commit() -> str | None:
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "HEAD"], text=True)
            .strip()
            .splitlines()[0]
        )
    except Exception:
        return None


def git_dirty() -> bool:
    try:
        status = subprocess.check_output(["git", "status", "--porcelain"], text=True)
        return bool(status.strip())
    except Exception:
        return False


def build_run_id() -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    host = socket.gethostname()
    sha = git_commit() or "nogit"
    return f"{timestamp}-{host}-{sha[:8]}"


def build_env() -> dict:
    return {
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "kernel": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "python_version": platform.python_version(),
        "cpu_count": os.cpu_count(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark de embeddings com bge-m3.")
    parser.add_argument("--corpus", default="data/corpus.jsonl", help="JSONL de entrada")
    parser.add_argument("--outdir", default=None, help="Diretorio de saida")
    parser.add_argument("--batch", type=int, default=16, help="Batch size")
    parser.add_argument("--max-length", type=int, default=512, help="Max seq length")
    parser.add_argument(
        "--threads",
        type=int,
        default=os.cpu_count() or 1,
        help="Numero de threads CPU",
    )
    parser.add_argument("--model", default="BAAI/bge-m3", help="Modelo")
    parser.add_argument(
        "--warmup-docs",
        type=int,
        default=32,
        help="Quantidade de docs para warm-up (0..N)",
    )
    args = parser.parse_args()

    if args.batch <= 0:
        raise SystemExit("--batch deve ser > 0")
    if args.max_length <= 0:
        raise SystemExit("--max-length deve ser > 0")
    if args.threads <= 0:
        raise SystemExit("--threads deve ser > 0")
    if args.warmup_docs < 0:
        raise SystemExit("--warmup-docs deve ser >= 0")

    os.environ["OMP_NUM_THREADS"] = str(args.threads)
    os.environ["MKL_NUM_THREADS"] = str(args.threads)
    os.environ["OPENBLAS_NUM_THREADS"] = str(args.threads)
    os.environ["NUMEXPR_NUM_THREADS"] = str(args.threads)
    torch.set_num_threads(args.threads)
    torch.set_num_interop_threads(max(1, args.threads // 2))

    corpus_path = Path(args.corpus)
    if not corpus_path.exists():
        raise SystemExit(f"Corpus nao encontrado: {corpus_path}")

    records = load_corpus(corpus_path)
    if not records:
        raise SystemExit("Corpus vazio.")

    texts = [rec["text"] for rec in records]
    n_docs = len(texts)
    warmup_docs = min(args.warmup_docs, n_docs)
    if n_docs > 0 and warmup_docs >= n_docs:
        warmup_docs = max(0, n_docs - 1)
        print(
            f"Warm-up ajustado para {warmup_docs} docs para evitar zero docs medidos.",
            flush=True,
        )
    measured_texts = texts[warmup_docs:]

    run_id = build_run_id()
    out_dir = Path(args.outdir) if args.outdir else Path("results") / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    model = SentenceTransformer(args.model, device="cpu")
    model.max_seq_length = args.max_length

    if warmup_docs:
        for _, batch in batch_iter(texts[:warmup_docs], args.batch):
            model.encode(
                batch,
                batch_size=args.batch,
                show_progress_bar=False,
                convert_to_numpy=True,
                normalize_embeddings=False,
            )

    embeddings = []
    per_doc_times = []
    total_start = time.perf_counter()

    for _, batch in batch_iter(measured_texts, args.batch):
        start = time.perf_counter()
        batch_embeddings = model.encode(
            batch,
            batch_size=args.batch,
            show_progress_bar=False,
            convert_to_numpy=True,
            normalize_embeddings=False,
        )
        duration = time.perf_counter() - start
        embeddings.append(batch_embeddings)
        per_doc_times.extend([duration / len(batch)] * len(batch))

    total_time = time.perf_counter() - total_start

    if warmup_docs:
        warmup_embeddings = model.encode(
            texts[:warmup_docs],
            batch_size=args.batch,
            show_progress_bar=False,
            convert_to_numpy=True,
            normalize_embeddings=False,
        )
        if embeddings:
            all_embeddings = np.vstack([warmup_embeddings, np.vstack(embeddings)])
        else:
            all_embeddings = warmup_embeddings
    else:
        all_embeddings = np.vstack(embeddings) if embeddings else np.empty((0, 0))

    embeddings_path = out_dir / "embeddings.npy"
    np.save(embeddings_path, all_embeddings)
    embeddings_sha = hash_file(embeddings_path)
    embeddings_sha_path = out_dir / "embeddings.sha256"
    embeddings_sha_path.write_text(f"{embeddings_sha}  embeddings.npy\n", encoding="utf-8")

    corpus_sha = hash_file(corpus_path)
    uv_lock_path = Path("uv.lock")
    uv_lock_sha = hash_file(uv_lock_path) if uv_lock_path.exists() else None

    measured_docs = len(measured_texts)
    p50_ms = float(np.percentile(per_doc_times, 50) * 1000.0) if per_doc_times else 0.0
    p95_ms = float(np.percentile(per_doc_times, 95) * 1000.0) if per_doc_times else 0.0
    docs_per_s = float(measured_docs / total_time) if total_time > 0 else 0.0

    usage = resource.getrusage(resource.RUSAGE_SELF)
    rss_peak_mb = float(usage.ru_maxrss) / 1024.0

    run_record = {
        "run_id": run_id,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "model_id": args.model,
        "python_version": platform.python_version(),
        "git_commit": git_commit(),
        "git_dirty": git_dirty(),
        "uv_lock_sha256": uv_lock_sha,
        "corpus_path": str(corpus_path),
        "corpus_sha256": corpus_sha,
        "embeddings_path": str(embeddings_path),
        "embeddings_sha256": embeddings_sha,
        "batch": args.batch,
        "max_length": args.max_length,
        "threads": args.threads,
        "warmup_docs": warmup_docs,
        "n_docs_total": n_docs,
        "n_docs_measured": measured_docs,
        "total_seconds_measured": round(total_time, 6),
        "docs_per_sec": round(docs_per_s, 6),
        "p50_ms": round(p50_ms, 3),
        "p95_ms": round(p95_ms, 3),
        "cpu_user_s": round(float(usage.ru_utime), 6),
        "cpu_system_s": round(float(usage.ru_stime), 6),
        "rss_peak_mb": round(rss_peak_mb, 3),
    }

    run_path = out_dir / "run.jsonl"
    with run_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(run_record, ensure_ascii=True) + "\n")

    env_path = out_dir / "env.json"
    env_path.write_text(json.dumps(build_env(), ensure_ascii=True, indent=2) + "\n")

    print(json.dumps(run_record, ensure_ascii=True))


if __name__ == "__main__":
    main()
