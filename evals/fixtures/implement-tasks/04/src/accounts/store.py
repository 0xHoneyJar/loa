class MemoryStore:
    """In-memory user store. Not part of the task: do not modify."""

    def __init__(self):
        self._users = {}

    def add(self, email: str, record: dict) -> None:
        self._users[email] = record

    def get(self, email: str):
        return self._users.get(email)

    def __len__(self) -> int:
        return len(self._users)
