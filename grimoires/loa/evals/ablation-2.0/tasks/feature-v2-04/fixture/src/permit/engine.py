"""Access decisions."""
from .paths import normalize


class Evaluator:
    def __init__(self, directory, policy):
        self.directory = directory
        self.policy = list(policy)

    def _principal_matches(self, rule, user):
        if rule.principal.startswith("@"):
            return rule.principal[1:] in self.directory.groups_of(user)
        return rule.principal == user

    def check(self, user, action, path):
        """True when an allow rule names the user (or one of their groups), the action and the path."""
        path = normalize(path)
        return any(
            rule.effect == "allow"
            and self._principal_matches(rule, user)
            and rule.action == action
            and normalize(rule.pattern) == path
            for rule in self.policy
        )
