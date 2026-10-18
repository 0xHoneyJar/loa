"""What happens to a block when it is closed."""


def _ends_with_blank_line(node):
    """True when the last line of ``node`` (or of its last descendant item) was blank."""
    while node is not None:
        if node.last_line_blank:
            return True
        if node.kind in ("list", "item") and node.children:
            node = node.children[-1]
        else:
            return False
    return False


def _code_block(node):
    if node.fenced:
        first, _, rest = node.content.partition("\n")
        node.info = first.strip(" ")
        node.literal = rest
    else:
        lines = node.content.split("\n")
        while lines and lines[-1].strip(" ") == "":
            lines.pop()
        node.literal = "\n".join(lines) + "\n"
    node.content = ""


def _item(node):
    if node.children:
        node.end_line = node.children[-1].end_line
    else:
        node.end_line = node.start_line


def _list(node):
    data = node.list_data
    for item in node.children:
        if item.next_sibling is not None and _ends_with_blank_line(item):
            data.tight = False
            return


def _nothing(node):
    pass


FINALIZE = {
    "code_block": _code_block,
    "item": _item,
    "list": _list,
}


def finalize_block(node):
    FINALIZE.get(node.kind, _nothing)(node)
