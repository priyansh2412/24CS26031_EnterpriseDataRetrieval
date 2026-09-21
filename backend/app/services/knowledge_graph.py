"""Sprint extension point for entity/relation extraction.

Persist extracted triples in a `knowledge_graph_edges` table and expose them via a graph
visualization once the project needs relationship-aware retrieval.
"""
from dataclasses import dataclass

@dataclass
class Triple:
    subject: str
    predicate: str
    object: str

def extract_triples(_: str) -> list[Triple]:
    # Replace with structured LLM output (JSON schema) and validation in a later sprint.
    return []
