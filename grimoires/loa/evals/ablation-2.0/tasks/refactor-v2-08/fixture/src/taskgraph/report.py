from .util import format_duration


def render(graph, slots):
    """Render a schedule and its summary."""
    w1 = max(len(s[0]) for s in slots)
    spans = ["%d-%d" % (s[1], s[2]) for s in slots]
    w2 = max(len(x) for x in spans)
    lines = []
    for s, span in zip(slots, spans):
        lines.append("%s  %s  w%d" % (s[0].ljust(w1), span.ljust(w2), s[3]))
    from .graph import critical_path
    total, path = critical_path(graph)
    lines.append("")
    lines.append("tasks: %d" % len(graph.tasks))
    lines.append("work: %s" % format_duration(sum(t.duration for t in graph.tasks)))
    lines.append("makespan: %s" % format_duration(max(s[2] for s in slots)))
    lines.append("critical: %s (%s)" % (" > ".join(path), format_duration(total)))
    return "\n".join(lines)


def toDot(graph):
    """Render a graph in Graphviz dot syntax."""
    out = ["digraph tasks {"]
    for t in graph.tasks:
        out.append('  "%s" [label="%s (%s)"];' % (t.name, t.name, format_duration(t.duration)))
    for t in graph.tasks:
        for d in t.needs:
            out.append('  "%s" -> "%s";' % (d, t.name))
    out.append("}")
    return "\n".join(out)
