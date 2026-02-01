#!/usr/bin/env python3
"""
Embedding service for Loa Memory Stack.
Uses sentence-transformers with all-MiniLM-L6-v2 model.

Usage:
    echo "text to embed" | python3 embed.py
    python3 embed.py --text "text to embed"
    python3 embed.py --check  # Check if model is available

Output:
    {"embedding": [0.1, 0.2, ...]} on success
    {"error": "message"} on failure
"""
import sys
import os
import json
import argparse
import hashlib

# Cache directory for model
CACHE_DIR = os.path.expanduser("~/.cache/sentence_transformers")
MODEL_NAME = "all-MiniLM-L6-v2"
EMBEDDING_DIM = 384

# Lazy load model (cached after first use)
_model = None


def get_model():
    """Load model lazily, cached after first use."""
    global _model
    if _model is None:
        try:
            from sentence_transformers import SentenceTransformer
            _model = SentenceTransformer(MODEL_NAME, cache_folder=CACHE_DIR)
        except ImportError:
            raise RuntimeError(
                "sentence-transformers not installed. "
                "Run: pip install sentence-transformers"
            )
    return _model


def embed(text: str) -> list:
    """Generate embedding for text.

    Args:
        text: Text to embed (max 512 tokens)

    Returns:
        List of floats (384 dimensions for all-MiniLM-L6-v2)
    """
    model = get_model()
    embedding = model.encode(text, convert_to_numpy=True)
    return embedding.tolist()


def cosine_similarity(vec1: list, vec2: list) -> float:
    """Calculate cosine similarity between two vectors."""
    import math

    dot_product = sum(a * b for a, b in zip(vec1, vec2))
    magnitude1 = math.sqrt(sum(a * a for a in vec1))
    magnitude2 = math.sqrt(sum(b * b for b in vec2))

    if magnitude1 == 0 or magnitude2 == 0:
        return 0.0

    return dot_product / (magnitude1 * magnitude2)


def check_availability() -> dict:
    """Check if embedding model is available."""
    try:
        from sentence_transformers import SentenceTransformer
        # Just check import, don't load model
        return {
            "available": True,
            "model": MODEL_NAME,
            "dimension": EMBEDDING_DIM,
            "cache_dir": CACHE_DIR
        }
    except ImportError as e:
        return {
            "available": False,
            "error": str(e),
            "install": "pip install sentence-transformers"
        }


def main():
    """CLI interface."""
    parser = argparse.ArgumentParser(description="Loa Memory Stack embedding service")
    parser.add_argument("--text", "-t", help="Text to embed (alternative to stdin)")
    parser.add_argument("--check", "-c", action="store_true",
                        help="Check if model is available")
    parser.add_argument("--similarity", "-s", nargs=2, metavar=("TEXT1", "TEXT2"),
                        help="Calculate similarity between two texts")
    args = parser.parse_args()

    try:
        # Check mode
        if args.check:
            result = check_availability()
            print(json.dumps(result))
            sys.exit(0 if result.get("available") else 1)

        # Similarity mode
        if args.similarity:
            text1, text2 = args.similarity
            emb1 = embed(text1)
            emb2 = embed(text2)
            similarity = cosine_similarity(emb1, emb2)
            print(json.dumps({
                "similarity": round(similarity, 4),
                "text1": text1[:50] + "..." if len(text1) > 50 else text1,
                "text2": text2[:50] + "..." if len(text2) > 50 else text2
            }))
            sys.exit(0)

        # Embed mode
        if args.text:
            text = args.text
        else:
            # Read from stdin
            if sys.stdin.isatty():
                print(json.dumps({"error": "No input provided. Use --text or pipe text to stdin"}))
                sys.exit(1)
            text = sys.stdin.read().strip()

        if not text:
            print(json.dumps({"error": "Empty input"}))
            sys.exit(1)

        # Truncate if too long (model max is ~512 tokens)
        if len(text) > 8000:
            text = text[:8000]

        embedding = embed(text)

        # Include hash for deduplication
        content_hash = hashlib.sha256(text.encode()).hexdigest()[:16]

        print(json.dumps({
            "embedding": embedding,
            "dimension": len(embedding),
            "content_hash": content_hash
        }))

    except RuntimeError as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": f"Unexpected error: {str(e)}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
