# Adjudication list — pr-83

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H07: anchors


Annotator A:

```json
{
  "anchor_lines": [
    2292,
    2293,
    2294,
    2295,
    2296,
    2297,
    2298,
    2299,
    2300,
    2301,
    2302,
    2303,
    2304,
    2305,
    2306,
    2307,
    2308,
    2309,
    2310
  ],
  "category": "logic",
  "description": "Removing a Fragment vnode that carries a transition bypasses the leave transition and afterLeave (removed immediately via removeFragment, or via a dev-only DEV_ROOT_FRAGMENT path), so production and dev behave differently and out-in transitions are not run/released.",
  "file": "packages/runtime-core/src/renderer.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    2292,
    2293,
    2294,
    2295,
    2296,
    2297,
    2298,
    2299,
    2300,
    2307,
    2308,
    2310
  ],
  "category": "logic",
  "description": "Removing a Fragment that carries a transition removes its DOM right away (or only handles the DEV root-fragment case), so the leave transition never runs and afterLeave is never called, which can leave out-in transitions stuck in production builds.",
  "file": "packages/runtime-core/src/renderer.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H08

```json
{
  "A": "performRemove only removes the single el node, so it cannot correctly remove a fragment's full DOM range after its leave transition.",
  "B": "performRemove only calls hostRemove on the single el, so it cannot remove a transitioning fragment's full range of nodes after leave."
}
```

- H09

```json
{
  "A": "The leave-transition check tests the vnode's own ELEMENT shape flag, so a fragment whose transition root is an element never gets its leave transition.",
  "B": "The leave-transition check tests the vnode's own ELEMENT shape flag, so it never matches a fragment whose transition root is an element."
}
```

- H10

```json
{
  "A": "leave/delayLeave are invoked on vnode.el rather than the transition root element, which is wrong for fragment vnodes whose el is the fragment start anchor.",
  "B": "leave and delayLeave are given the vnode's el, which for a fragment is the start anchor rather than the transitioning root element."
}
```
