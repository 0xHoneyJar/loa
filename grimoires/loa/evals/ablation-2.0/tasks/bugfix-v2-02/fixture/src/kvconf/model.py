"""The Config model and the errors of kvconf."""


class ConfigError(ValueError):
    """A section, key or value is not acceptable."""


class ParseError(ConfigError):
    def __init__(self, line, message):
        super().__init__(f"line {line}: {message}")
        self.line = line


def norm(name):
    """A section or key name as names are compared."""
    return name.strip().casefold()


def _check_name(kind, name):
    if not isinstance(name, str) or not name.strip():
        raise ConfigError(f"empty {kind} name")
    if name != name.strip() or "\n" in name or "\r" in name:
        raise ConfigError(f"bad {kind} name: {name!r}")
    if kind == "key" and ("=" in name or name[0] in "#;["):
        raise ConfigError(f"bad key name: {name!r}")
    if kind == "section" and ("]" in name or "[" in name):
        raise ConfigError(f"bad section name: {name!r}")


class Config:
    """Ordered sections of ordered key/value pairs."""

    def __init__(self):
        self._sections = []  # [name, [[key, value], ...]]

    def __eq__(self, other):
        if not isinstance(other, Config):
            return NotImplemented
        return self._sections == other._sections

    def __repr__(self):
        return f"Config({self._sections!r})"

    def _find(self, name):
        wanted = norm(name)
        for entry in self._sections:
            if norm(entry[0]) == wanted:
                return entry
        return None

    def add_section(self, name):
        _check_name("section", name)
        for entry in self._sections:
            if entry[0] == name:
                return entry[0]
        self._sections.append([name, []])
        return name

    def set(self, section, key, value):
        _check_name("key", key)
        if not isinstance(value, str):
            raise ConfigError(f"value of {key} must be a string")
        self.add_section(section)
        for entry in self._sections:
            if entry[0] == section:
                break
        for pair in entry[1]:
            if pair[0] == key:
                pair[1] = value
                return
        entry[1].append([key, value])

    def get(self, section, key, default=None):
        entry = self._find(section)
        if entry is None:
            return default
        wanted = norm(key)
        for name, value in entry[1]:
            if norm(name) == wanted:
                return value
        return default

    def sections(self):
        return [entry[0] for entry in self._sections]

    def _pairs(self, section):
        entry = self._find(section)
        if entry is None:
            raise ConfigError(f"no such section: {section}")
        return entry[1]

    def keys(self, section):
        return [key for key, _ in self._pairs(section)]

    def items(self, section):
        return [(key, value) for key, value in self._pairs(section)]
