"""
Hybrid Matcher - Keyword, fuzzy, and embedding matching.

Matches feedback text against the feedback ontology using:
1. Exact keyword matching (always available)
2. Fuzzy matching with rapidfuzz (optional)
3. Semantic embedding matching with sentence-transformers (optional)
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import yaml

from .models import KeywordMatch, MatcherOutput

logger = logging.getLogger(__name__)

# Configuration
MIN_FUZZY_LENGTH = 5
MAX_FUZZY_COMPARISONS = 1000
DEFAULT_FUZZY_THRESHOLD = 80
DEFAULT_EMBEDDING_THRESHOLD = 0.7

# Default ontology path (relative to script location)
def _get_default_ontology_path() -> Path:
    """Get the default ontology path relative to this module."""
    module_dir = Path(__file__).parent
    # Go up to .claude/scripts, then to .claude/loa
    return module_dir.parent.parent / "loa" / "feedback-ontology.yaml"

DEFAULT_ONTOLOGY_PATH = _get_default_ontology_path()


class HybridMatcher:
    """
    Hybrid matching engine combining keyword, fuzzy, and embedding approaches.

    Gracefully degrades when optional dependencies are unavailable.
    """

    def __init__(
        self,
        ontology_path: str | Path = DEFAULT_ONTOLOGY_PATH,
        fuzzy_threshold: int = DEFAULT_FUZZY_THRESHOLD,
        embedding_threshold: float = DEFAULT_EMBEDDING_THRESHOLD,
    ):
        self.ontology_path = Path(ontology_path)
        self.fuzzy_threshold = fuzzy_threshold
        self.embedding_threshold = embedding_threshold

        # Load ontology
        self.ontology = self._load_ontology()

        # Check optional dependencies
        self._rapidfuzz_available = self._check_rapidfuzz()
        self._embeddings_available = self._check_embeddings()

        # Pre-compute embeddings if available
        self._domain_embeddings: dict[str, Any] = {}
        if self._embeddings_available:
            self._precompute_embeddings()

    def _load_ontology(self) -> dict[str, Any]:
        """Load the feedback ontology YAML."""
        if not self.ontology_path.exists():
            logger.warning(f"Ontology not found at {self.ontology_path}")
            return {"domains": {}}

        try:
            with open(self.ontology_path, "r") as f:
                return yaml.safe_load(f) or {"domains": {}}
        except Exception as e:
            logger.error(f"Failed to load ontology: {e}")
            return {"domains": {}}

    def _check_rapidfuzz(self) -> bool:
        """Check if rapidfuzz is available."""
        try:
            import rapidfuzz
            return True
        except ImportError:
            logger.info("rapidfuzz not available, fuzzy matching disabled")
            return False

    def _check_embeddings(self) -> bool:
        """Check if sentence-transformers is available."""
        try:
            from sentence_transformers import SentenceTransformer
            return True
        except ImportError:
            logger.info("sentence-transformers not available, embedding matching disabled")
            return False

    def _precompute_embeddings(self) -> None:
        """Pre-compute embeddings for domain descriptions."""
        if not self._embeddings_available:
            return

        try:
            from sentence_transformers import SentenceTransformer

            # Use a small, fast model
            model = SentenceTransformer("all-MiniLM-L6-v2")

            domains = self.ontology.get("domains", {})
            for domain_name, domain_data in domains.items():
                description = domain_data.get("description", domain_name)
                self._domain_embeddings[domain_name] = model.encode(description)

            logger.info(f"Pre-computed embeddings for {len(self._domain_embeddings)} domains")
        except Exception as e:
            logger.warning(f"Failed to pre-compute embeddings: {e}")
            self._embeddings_available = False

    def match(self, text: str) -> MatcherOutput:
        """
        Match text against the ontology using all available methods.

        Args:
            text: The feedback text to match

        Returns:
            MatcherOutput with all match types
        """
        output = MatcherOutput()

        # Track missing dependencies
        if not self._rapidfuzz_available:
            output.dependency_missing.append("rapidfuzz")
        if not self._embeddings_available:
            output.dependency_missing.append("sentence-transformers")

        # 1. Keyword matching (always available)
        output.keyword_matches = self._keyword_match(text)

        # 2. Fuzzy matching (if available)
        if self._rapidfuzz_available:
            output.fuzzy_matches = self._fuzzy_match(text)

        # 3. Embedding matching (if available)
        if self._embeddings_available:
            output.embedding_matches = self._embedding_match(text)

        # Aggregate matched skills and domains
        all_matches = (
            output.keyword_matches +
            output.fuzzy_matches +
            output.embedding_matches
        )

        output.matched_skills = list(set(
            m.skill for m in all_matches if m.skill
        ))
        output.matched_domains = list(set(
            m.domain for m in all_matches
        ))

        return output

    def _keyword_match(self, text: str) -> list[KeywordMatch]:
        """Exact keyword matching against ontology."""
        matches = []
        text_lower = text.lower()

        domains = self.ontology.get("domains", {})
        for domain_name, domain_data in domains.items():
            keywords = domain_data.get("keywords", [])
            skills = domain_data.get("skills", [])

            for keyword in keywords:
                if keyword.lower() in text_lower:
                    matches.append(KeywordMatch(
                        keyword=keyword,
                        domain=domain_name,
                        skill=skills[0] if skills else None,
                        match_type="exact",
                        score=1.0,
                    ))

        return matches

    def _fuzzy_match(self, text: str) -> list[KeywordMatch]:
        """Fuzzy matching using rapidfuzz."""
        if not self._rapidfuzz_available:
            return []

        try:
            from rapidfuzz import fuzz, process

            matches = []
            text_lower = text.lower()

            # Only fuzzy match words of sufficient length
            words = [w for w in text_lower.split() if len(w) >= MIN_FUZZY_LENGTH]
            if not words:
                return []

            # Collect all keywords for matching
            all_keywords: list[tuple[str, str, str | None]] = []
            domains = self.ontology.get("domains", {})
            for domain_name, domain_data in domains.items():
                keywords = domain_data.get("keywords", [])
                skills = domain_data.get("skills", [])
                for keyword in keywords:
                    if len(keyword) >= MIN_FUZZY_LENGTH:
                        all_keywords.append((
                            keyword,
                            domain_name,
                            skills[0] if skills else None,
                        ))

            # Cap comparisons
            comparisons = 0
            for word in words:
                if comparisons >= MAX_FUZZY_COMPARISONS:
                    break

                for keyword, domain, skill in all_keywords:
                    if comparisons >= MAX_FUZZY_COMPARISONS:
                        break

                    score = fuzz.ratio(word, keyword.lower())
                    comparisons += 1

                    if score >= self.fuzzy_threshold:
                        matches.append(KeywordMatch(
                            keyword=keyword,
                            domain=domain,
                            skill=skill,
                            match_type="fuzzy",
                            score=score / 100.0,
                        ))

            return matches
        except Exception as e:
            logger.warning(f"Fuzzy matching failed: {e}")
            return []

    def _embedding_match(self, text: str) -> list[KeywordMatch]:
        """Semantic embedding matching using sentence-transformers."""
        if not self._embeddings_available or not self._domain_embeddings:
            return []

        try:
            from sentence_transformers import SentenceTransformer
            import numpy as np

            model = SentenceTransformer("all-MiniLM-L6-v2")
            text_embedding = model.encode(text)

            matches = []
            domains = self.ontology.get("domains", {})

            for domain_name, domain_embedding in self._domain_embeddings.items():
                # Cosine similarity
                similarity = np.dot(text_embedding, domain_embedding) / (
                    np.linalg.norm(text_embedding) * np.linalg.norm(domain_embedding)
                )

                if similarity >= self.embedding_threshold:
                    domain_data = domains.get(domain_name, {})
                    skills = domain_data.get("skills", [])
                    matches.append(KeywordMatch(
                        keyword=domain_name,
                        domain=domain_name,
                        skill=skills[0] if skills else None,
                        match_type="embedding",
                        score=float(similarity),
                    ))

            return matches
        except Exception as e:
            logger.warning(f"Embedding matching failed: {e}")
            return []
