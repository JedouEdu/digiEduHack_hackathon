"""LLM client for entity extraction and sentiment analysis using Featherless.ai.

This module provides an interface to Featherless.ai for LLM-based tasks like
entity extraction from text and sentiment analysis using Llama 3.3 70B.
"""

import json
import logging
from typing import Any

from openai import OpenAI

from eduscale.core.config import settings

logger = logging.getLogger(__name__)


class LLMClient:
    """Client for interacting with Featherless.ai LLM API (Llama via OpenAI-compatible endpoint)."""

    def __init__(self, model: str | None = None):
        """Initialize LLM client.

        Args:
            model: Model name (default: from settings)
        """
        self.model_name = model or settings.FEATHERLESS_LLM_MODEL
        self.enabled = settings.LLM_ENABLED
        self._client = None

        if not self.enabled:
            logger.warning("LLM is disabled in settings")
        else:
            self._init_client()

    def _init_client(self):
        """Initialize Featherless.ai client."""
        try:
            logger.info(f"Initializing Featherless.ai LLM client: {self.model_name}")
            self._client = OpenAI(
                base_url=settings.FEATHERLESS_BASE_URL,
                api_key=settings.FEATHERLESS_API_KEY,
            )
            logger.info(f"Featherless.ai LLM client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Featherless.ai LLM: {e}")
            raise

    def extract_entities(self, text: str) -> list[dict[str, str]]:
        """Extract named entities from text using LLM.

        Args:
            text: Input text (Czech or English)

        Returns:
            List of entities with format: [{"text": "name", "type": "person|subject|location"}]
            Returns empty list if LLM is disabled or extraction fails
        """
        if not self.enabled or self._client is None:
            logger.debug("LLM disabled, skipping entity extraction")
            return []

        if not text or not text.strip():
            return []

        prompt = f"""Extract person names, subjects, and locations from this Czech/English educational text.
Return ONLY a JSON array with this exact format: [{{"text": "name", "type": "person|subject|location"}}]
Do not include any explanation, only the JSON array.

Text: {text}

JSON:"""

        try:
            response = self._call_llm(prompt, max_tokens=200)
            # Try to parse JSON response
            entities = json.loads(response.strip())

            if not isinstance(entities, list):
                logger.warning(f"LLM returned non-list response: {response}")
                return []

            # Validate entity format
            valid_entities = []
            for entity in entities:
                if isinstance(entity, dict) and "text" in entity and "type" in entity:
                    valid_entities.append(entity)
                else:
                    logger.warning(f"Invalid entity format: {entity}")

            logger.info(f"Extracted {len(valid_entities)} entities from text")
            return valid_entities

        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse LLM response as JSON: {e}, response: {response}")
            return []
        except Exception as e:
            logger.error(f"Entity extraction failed: {e}")
            return []

    def analyze_sentiment(self, text: str) -> float:
        """Analyze sentiment using LLM.

        Args:
            text: Input text (Czech or English)

        Returns:
            Sentiment score from -1.0 (very negative) to +1.0 (very positive)
            Returns 0.0 if LLM is disabled or analysis fails
        """
        if not self.enabled or self._client is None:
            logger.debug("LLM disabled, skipping sentiment analysis")
            return 0.0

        if not text or not text.strip():
            return 0.0

        prompt = f"""Analyze the sentiment of this educational feedback (Czech/English).
Return ONLY a single number from -1.0 (very negative) to +1.0 (very positive).
Do not include any explanation, only the number.

Text: {text}

Score:"""

        try:
            response = self._call_llm(prompt, max_tokens=10)
            score = float(response.strip())

            # Clamp to valid range
            score = max(-1.0, min(1.0, score))

            logger.info(f"Sentiment score: {score:.3f}")
            return score

        except ValueError as e:
            logger.warning(f"Failed to parse sentiment score: {e}, response: {response}")
            return 0.0
        except Exception as e:
            logger.error(f"Sentiment analysis failed: {e}")
            return 0.0

    def _call_llm(self, prompt: str, max_tokens: int = 500) -> str:
        """Internal method to call Featherless.ai LLM API.

        Args:
            prompt: Prompt text
            max_tokens: Maximum tokens to generate

        Returns:
            Generated text response

        Raises:
            Exception: If API call fails
        """
        try:
            response = self._client.chat.completions.create(
                model=self.model_name,
                messages=[
                    {"role": "user", "content": prompt}
                ],
                max_tokens=max_tokens,
                temperature=0.1,  # Low temperature for deterministic outputs
            )

            return response.choices[0].message.content

        except Exception as e:
            logger.error(f"Featherless.ai LLM call failed: {e}")
            raise
