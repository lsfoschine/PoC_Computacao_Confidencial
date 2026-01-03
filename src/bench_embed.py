import argparse
import json
import os
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

import numpy as np
from sentence_transformers import SentenceTransformer

load_dotenv()


def load_corpus(path: Path, limit: int | None) -> list[dict]:
    records = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            records.append(json.loads(line))
            if limit and len(records) >= limit:
                break
    return records


def batch_iter(items: list[str], batch_size: int):
    for idx in range(0, len(items), batch_size):
        yield idx, items[idx : idx + batch_size]


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark de embeddings com bge-m3.")
    parser.add_argument("--corpus", default="data/corpus.jsonl", help="JSONL de entrada")
    parser.add_argument("--model", default="BAAI/bge-m3", help="Modelo")
    parser.add_argument("--seq-len", type=int, default=512, help="Max seq length")
    parser.add_argument("--batch-size", type=int, default=16, help="Batch size")
    parser.add_argument("--limit", type=int, default=None, help="Limite de docs")
    parser.add_argument("--out-dir", default="results", help="Diretorio de saida")
    args = parser.parse_args()

    corpus_path = Path(args.corpus)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    records = load_corpus(corpus_path, args.limit)
    if not records:
        raise SystemExit("Corpus vazio.")
    texts = [rec["text"] for rec in records]

    model = SentenceTransformer(args.model, device="cpu")
    model.max_seq_length = args.seq_len

    embeddings = []
    per_doc_times = []
    total_start = time.perf_counter()

    for _, batch in batch_iter(texts, args.batch_size):
        start = time.perf_counter()
        batch_embeddings = model.encode(
            batch,
            batch_size=args.batch_size,
            show_progress_bar=False,
            convert_to_numpy=True,
            normalize_embeddings=False,
        )
        duration = time.perf_counter() - start
        embeddings.append(batch_embeddings)
        per_doc_times.extend([duration / len(batch)] * len(batch))

    total_time = time.perf_counter() - total_start
    all_embeddings = np.vstack(embeddings)

    embeddings_path = out_dir / "embeddings.npy"
    np.save(embeddings_path, all_embeddings)

    p50_ms = float(np.percentile(per_doc_times, 50) * 1000.0)
    p95_ms = float(np.percentile(per_doc_times, 95) * 1000.0)
    docs_per_s = float(len(texts) / total_time) if total_time > 0 else 0.0

    run_record = {
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "model": args.model,
        "seq_len": args.seq_len,
        "batch_size": args.batch_size,
        "num_docs": len(texts),
        "p50_ms": round(p50_ms, 3),
        "p95_ms": round(p95_ms, 3),
        "docs_per_s": round(docs_per_s, 3),
        "total_s": round(total_time, 3),
        "corpus_path": str(corpus_path),
        "embeddings_path": str(embeddings_path),
    }

    run_path = out_dir / "run.jsonl"
    with run_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(run_record, ensure_ascii=True) + "\n")

    print(json.dumps(run_record, ensure_ascii=True))


if __name__ == "__main__":
    main()
