"""Config -> text."""
from .escape import quote


def needs_quotes(value):
    """Whether ``value`` cannot be written bare."""
    return (value == "" or value[0].isspace() or value[0] == '"'
            or any(ch in value for ch in '\\"\n\t\r'))


def format_value(value):
    return quote(value) if needs_quotes(value) else value


def dumps(config):
    """The file text of ``config``: one block per section, blank-line separated."""
    blocks = []
    for section in config.sections():
        lines = [f"[{section}]"]
        lines += [f"{key} = {format_value(value)}" for key, value in config.items(section)]
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks) + "\n" if blocks else ""
