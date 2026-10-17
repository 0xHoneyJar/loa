"""The outcome of one batch."""
from dataclasses import dataclass, field

COMMITTED = "committed"
ROLLED_BACK = "rolled back"


@dataclass
class Report:
    status: str = COMMITTED
    attempted: list = field(default_factory=list)
    skipped: list = field(default_factory=list)
    failed: str = None
    error: str = None

    @property
    def applied(self):
        """Ids applied by the batch, in item order."""
        return [i for i in self.attempted if i not in self.skipped]

    def note(self, item_id, outcome):
        self.attempted.append(item_id)
        if outcome == "skipped":
            self.skipped.append(item_id)

    def fail(self, item_id, error):
        self.attempted.append(item_id)
        self.status = ROLLED_BACK
        self.failed = item_id
        self.error = error

    def summary(self):
        if self.status == ROLLED_BACK:
            return f"rolled back at {self.failed}: {self.error}"
        return f"committed: {len(self.applied)} applied, {len(self.skipped)} skipped"
